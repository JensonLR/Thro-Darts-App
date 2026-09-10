package thro.api

import java.security.MessageDigest
import java.security.SecureRandom
import java.sql.Connection
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.util.Base64
import java.util.UUID

/**
 * Accounts and sessions (PD-030, ADR-008). The provider proved who is holding the phone; from here
 * on the session is THRØ's own.
 *
 *  - A first sign-in creates, in one transaction, an account, a player and the `self_created` claim
 *    binding them, and the credential. A later sign-in with the same subject finds the account.
 *  - An access token is 32 random bytes, base64url; only its SHA-256 is stored; it is looked up per
 *    request and names an account. The account's live claim is the principal.
 *  - A refresh token is single-use. Using it issues a new pair and marks it used with its successor.
 *    Using it again is reuse — the sign a copy exists — and revokes the whole family.
 */
public class Accounts(
    private val connection: Connection,
    private val now: () -> Instant = { Instant.now() },
    private val random: SecureRandom = SecureRandom(),
) {
    /** [playerId] is null when the account's claim has been revoked: authenticated, but no THRØ ID until it is re-claimed. */
    public data class Session(val accountId: UUID, val playerId: UUID?, val accessToken: String, val refreshToken: String, val accessExpiresAt: Instant, val created: Boolean)

    /** The account behind this credential was deleted; there is nothing to sign in to. */
    public class AccountDeleted : IllegalStateException("this account was deleted")

    public sealed interface Refreshed {
        public data class Rotated(val session: Session) : Refreshed
        /** The token had been used before. The family is now revoked, and this says so. */
        public data object Reused : Refreshed
        public data object Unknown : Refreshed
        public data object Expired : Refreshed
    }

    public data class Profile(val accountId: UUID, val playerId: UUID?, val displayName: String, val ageBand: String, val named: Boolean, val credentials: Int)

    public companion object {
        public val ACCESS_TTL: Duration = Duration.ofMinutes(15)
        public val REFRESH_TTL: Duration = Duration.ofDays(30)
        public val CHALLENGE_TTL: Duration = Duration.ofMinutes(5)
        /** What a new account is called until the person says otherwise (§12d #9). */
        public const val PLACEHOLDER_NAME: String = "New player"
    }

    /**
     * Signs in the holder of a verified provider subject on [deviceId]; creates the account on first
     * sight. With [linkTo], a subject nobody holds is bound to that account instead — how a person
     * who started with a passkey adds Apple or Google, which is the recovery path PD-032 decides.
     */
    public fun signIn(kind: String, subject: String, deviceId: UUID, linkTo: UUID? = null): Session = transaction {
        var created = false
        // Two first sign-ins with one subject at once — the double tap every mobile flow produces —
        // take turns here, so the second finds the account the first created instead of failing on
        // the unique index.
        connection.prepareStatement("SELECT pg_advisory_xact_lock(hashtext(?))").use { ps -> ps.setString(1, "$kind:$subject"); ps.executeQuery().close() }
        var (credentialId, accountId) = connection.prepareStatement(
            """
            SELECT c.credential_id, c.account_id, a.deleted_at FROM identity.credential c JOIN identity.account a ON a.account_id = c.account_id
             WHERE c.kind = ? AND c.subject = ? AND c.revoked_at IS NULL
            """.trimIndent(),
        ).use { ps ->
            ps.setString(1, kind); ps.setString(2, subject)
            ps.executeQuery().use { rs ->
                if (rs.next()) {
                    if (rs.getTimestamp(3) != null) throw AccountDeleted()
                    (rs.getObject(1) as UUID) to (rs.getObject(2) as UUID)
                } else null to null
            }
        }
        if (accountId == null) {
            accountId = linkTo ?: newAccount().also { created = true }
            credentialId = UUID.randomUUID()
            connection.prepareStatement("INSERT INTO identity.credential (credential_id, account_id, kind, subject) VALUES (?, ?, ?, ?)")
                .use { ps -> ps.setObject(1, credentialId); ps.setObject(2, accountId); ps.setString(3, kind); ps.setString(4, subject); ps.executeUpdate() }
        }
        connection.prepareStatement("UPDATE identity.credential SET last_used_at = ? WHERE credential_id = ?")
            .use { ps -> ps.setObject(1, Timestamp.from(now())); ps.setObject(2, credentialId); ps.executeUpdate() }
        openFamily(credentialId!!, accountId!!, deviceId, created)
    }

    /** An account, its player and the claim binding them, in this transaction. */
    private fun newAccount(): UUID {
        val accountId = UUID.randomUUID()
        // created_via 'self' makes V016's trigger record the person's own consent at creation.
        connection.prepareStatement("INSERT INTO identity.account (account_id, display_name, created_via) VALUES (?, ?, 'self')")
            .use { ps -> ps.setObject(1, accountId); ps.setString(2, PLACEHOLDER_NAME); ps.executeUpdate() }
        val orgs = Organisations(connection)
        val playerId = orgs.createPlayer(source = "self", by = accountId)
        orgs.claim(playerId, accountId, method = "self_created")
        return accountId
    }

    // --- passkeys (V025) -----------------------------------------------------------------------

    public data class Challenge(val id: UUID, val bytes: ByteArray, val accountId: UUID?, val userHandle: ByteArray?)

    /** A fresh ceremony: 32 random bytes, five minutes, once. [accountId] when a passkey is added to an account. */
    public fun newChallenge(kind: String, deviceId: UUID, accountId: UUID? = null): Challenge {
        val id = UUID.randomUUID()
        val bytes = ByteArray(32).also(random::nextBytes)
        val handle = if (kind == "register" && accountId == null) ByteArray(32).also(random::nextBytes) else null
        connection.prepareStatement(
            "INSERT INTO identity.webauthn_challenge (challenge_id, kind, challenge, account_id, user_handle, device_id, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        ).use { ps ->
            ps.setObject(1, id); ps.setString(2, kind); ps.setBytes(3, bytes); ps.setObject(4, accountId); ps.setBytes(5, handle)
            ps.setObject(6, deviceId); ps.setObject(7, Timestamp.from(now().plus(CHALLENGE_TTL))); ps.executeUpdate()
        }
        return Challenge(id, bytes, accountId, handle)
    }

    /** Spends a challenge: null when it is unknown, of another kind, expired, already used, or another device's. */
    public fun takeChallenge(id: UUID, kind: String, deviceId: UUID): Challenge? = transaction {
        val row = connection.prepareStatement(
            "SELECT challenge, account_id, user_handle, expires_at, used_at, device_id FROM identity.webauthn_challenge WHERE challenge_id = ? AND kind = ? FOR UPDATE",
        ).use { ps ->
            ps.setObject(1, id); ps.setString(2, kind)
            ps.executeQuery().use { rs -> if (rs.next()) listOf(rs.getBytes(1), rs.getObject(2), rs.getBytes(3), rs.getTimestamp(4).toInstant(), rs.getTimestamp(5), rs.getObject(6)) else return@transaction null }
        }
        if (row[4] != null || (row[3] as Instant).isBefore(now()) || row[5] != deviceId) return@transaction null
        connection.prepareStatement("UPDATE identity.webauthn_challenge SET used_at = ? WHERE challenge_id = ?")
            .use { ps -> ps.setObject(1, Timestamp.from(now())); ps.setObject(2, id); ps.executeUpdate() }
        Challenge(id, row[0] as ByteArray, row[1] as UUID?, row[2] as ByteArray?)
    }

    /** Stores a verified passkey — on [accountId], or on a new account — and opens a session. */
    public fun registerPasskey(accountId: UUID?, credentialId: ByteArray, publicKeyCose: ByteArray, signCount: Long, deviceId: UUID): Session = transaction {
        val subject = Base64.getUrlEncoder().withoutPadding().encodeToString(credentialId)
        val account = accountId ?: newAccount()
        val id = UUID.randomUUID()
        connection.prepareStatement(
            "INSERT INTO identity.credential (credential_id, account_id, kind, subject, public_key, sign_count) VALUES (?, ?, 'passkey', ?, ?, ?)",
        ).use { ps -> ps.setObject(1, id); ps.setObject(2, account); ps.setString(3, subject); ps.setBytes(4, publicKeyCose); ps.setLong(5, signCount); ps.executeUpdate() }
        openFamily(id, account, deviceId, created = accountId == null)
    }

    public data class Passkey(val credentialId: UUID, val accountId: UUID, val publicKeyCose: ByteArray, val signCount: Long)

    public fun passkey(credentialId: ByteArray): Passkey? =
        connection.prepareStatement(
            """
            SELECT c.credential_id, c.account_id, c.public_key, c.sign_count FROM identity.credential c
              JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
             WHERE c.kind = 'passkey' AND c.subject = ? AND c.revoked_at IS NULL
            """.trimIndent(),
        ).use { ps ->
            ps.setString(1, Base64.getUrlEncoder().withoutPadding().encodeToString(credentialId))
            ps.executeQuery().use { rs -> if (rs.next()) Passkey(rs.getObject(1) as UUID, rs.getObject(2) as UUID, rs.getBytes(3), rs.getLong(4)) else null }
        }

    /** A verified assertion: the counter moves on and a session opens. */
    public fun signInWithPasskey(passkey: Passkey, newSignCount: Long, deviceId: UUID): Session = transaction {
        connection.prepareStatement("UPDATE identity.credential SET sign_count = ?, last_used_at = ? WHERE credential_id = ?")
            .use { ps -> ps.setLong(1, newSignCount); ps.setObject(2, Timestamp.from(now())); ps.setObject(3, passkey.credentialId); ps.executeUpdate() }
        openFamily(passkey.credentialId, passkey.accountId, deviceId, created = false)
    }

    private fun openFamily(credentialId: UUID, accountId: UUID, deviceId: UUID, created: Boolean): Session {
        val familyId = UUID.randomUUID()
        connection.prepareStatement("INSERT INTO identity.session_family (family_id, account_id, credential_id, device_id) VALUES (?, ?, ?, ?)")
            .use { ps -> ps.setObject(1, familyId); ps.setObject(2, accountId); ps.setObject(3, credentialId); ps.setObject(4, deviceId); ps.executeUpdate() }
        return issue(familyId, accountId, created)
    }

    /** How many live credentials an account has — the recovery question PD-032 asks. */
    public fun credentialCount(accountId: UUID): Int =
        connection.prepareStatement("SELECT count(*) FROM identity.credential WHERE account_id = ? AND revoked_at IS NULL")
            .use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) } }

    public fun refresh(refreshToken: String): Refreshed = transaction {
        val hash = sha256(refreshToken)
        // FOR UPDATE: two refreshes racing with one token serialise here, so the second sees the
        // first's used_at and is answered as reuse rather than failing on the trigger.
        val row = connection.prepareStatement(
            """
            SELECT r.family_id, r.expires_at, r.used_at, f.account_id, f.revoked_at, f.expires_at
              FROM identity.refresh_token r JOIN identity.session_family f ON f.family_id = r.family_id
             WHERE r.token_hash = ? FOR UPDATE OF r
            """.trimIndent(),
        ).use { ps ->
            ps.setBytes(1, hash)
            ps.executeQuery().use { rs ->
                if (!rs.next()) return@transaction Refreshed.Unknown
                listOf(rs.getObject(1), rs.getTimestamp(2).toInstant(), rs.getTimestamp(3)?.toInstant(), rs.getObject(4), rs.getTimestamp(5)?.toInstant(), rs.getTimestamp(6).toInstant())
            }
        }
        val familyId = row[0] as UUID; val expires = row[1] as Instant; val used = row[2] as Instant?; val accountId = row[3] as UUID; val revoked = row[4] as Instant?
        val familyExpires = row[5] as Instant
        if (revoked != null) return@transaction Refreshed.Unknown
        if (familyExpires.isBefore(now())) return@transaction Refreshed.Expired
        if (used != null) {
            // Reuse. Somebody holds a copy of a token that was already spent; nobody in this family
            // can be trusted, and the family goes — including whichever of the two is the thief.
            revokeFamily(familyId, "refresh token reused")
            return@transaction Refreshed.Reused
        }
        if (expires.isBefore(now())) return@transaction Refreshed.Expired
        val session = issue(familyId, accountId, created = false)
        connection.prepareStatement("UPDATE identity.refresh_token SET used_at = ?, superseded_by = ? WHERE token_hash = ?")
            .use { ps -> ps.setObject(1, Timestamp.from(now())); ps.setBytes(2, sha256(session.refreshToken)); ps.setBytes(3, hash); ps.executeUpdate() }
        Refreshed.Rotated(session)
    }

    /** Revokes the family the access token belongs to. True when there was one. */
    public fun logout(accessToken: String): Boolean = transaction {
        val family = connection.prepareStatement("SELECT family_id FROM identity.access_token WHERE token_hash = ?")
            .use { ps -> ps.setBytes(1, sha256(accessToken)); ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null } }
            ?: return@transaction false
        revokeFamily(family, "logout")
        true
    }

    /** The account and its live player for a presented access token, or null when it is unknown, expired or revoked. */
    public fun resolve(accessToken: String): Pair<UUID, UUID>? =
        connection.prepareStatement(
            """
            SELECT t.account_id, c.player_id
              FROM identity.access_token t
              JOIN identity.session_family f ON f.family_id = t.family_id
              JOIN identity.account a ON a.account_id = t.account_id AND a.deleted_at IS NULL
              LEFT JOIN identity.player_claim c ON c.account_id = t.account_id AND c.revoked_at IS NULL
             WHERE t.token_hash = ? AND t.expires_at > ? AND f.revoked_at IS NULL AND f.expires_at > ?
            """.trimIndent(),
        ).use { ps ->
            ps.setBytes(1, sha256(accessToken)); ps.setObject(2, Timestamp.from(now())); ps.setObject(3, Timestamp.from(now()))
            // An account whose claim was revoked is a real account with no THRØ ID: nobody, until re-claimed.
            ps.executeQuery().use { rs -> if (rs.next()) (rs.getObject(1) as UUID) to (rs.getObject(2) as UUID? ?: return null) else null }
        }

    public fun profile(accountId: UUID): Profile? =
        connection.prepareStatement(
            """
            SELECT a.display_name, a.age_band, c.player_id FROM identity.account a
              LEFT JOIN identity.player_claim c ON c.account_id = a.account_id AND c.revoked_at IS NULL
             WHERE a.account_id = ? AND a.deleted_at IS NULL
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, accountId)
            ps.executeQuery().use { rs -> if (rs.next()) Profile(accountId, rs.getObject(3) as UUID?, rs.getString(1), rs.getString(2), rs.getString(1) != PLACEHOLDER_NAME, credentialCount(accountId)) else null }
        }

    public fun setDisplayName(accountId: UUID, name: String) {
        val trimmed = name.trim()
        require(trimmed.isNotEmpty() && trimmed.codePointCount(0, trimmed.length) <= 60) { "a display name is 1 to 60 characters" }
        require(trimmed.none { it.isISOControl() || it.category == CharCategory.FORMAT }) { "a display name has no control or formatting characters" }
        val n = connection.prepareStatement("UPDATE identity.account SET display_name = ? WHERE account_id = ? AND deleted_at IS NULL")
            .use { ps -> ps.setString(1, trimmed); ps.setObject(2, accountId); ps.executeUpdate() }
        require(n == 1) { "no such account" }
    }

    // --- internals ------------------------------------------------------------------------------

    private fun issue(familyId: UUID, accountId: UUID, created: Boolean): Session {
        val access = token(); val refresh = token()
        val accessExpires = now().plus(ACCESS_TTL)
        connection.prepareStatement("INSERT INTO identity.access_token (token_hash, family_id, account_id, issued_at, expires_at) VALUES (?, ?, ?, ?, ?)")
            .use { ps -> ps.setBytes(1, sha256(access)); ps.setObject(2, familyId); ps.setObject(3, accountId); ps.setObject(4, Timestamp.from(now())); ps.setObject(5, Timestamp.from(accessExpires)); ps.executeUpdate() }
        connection.prepareStatement("INSERT INTO identity.refresh_token (token_hash, family_id, issued_at, expires_at) VALUES (?, ?, ?, ?)")
            .use { ps -> ps.setBytes(1, sha256(refresh)); ps.setObject(2, familyId); ps.setObject(3, Timestamp.from(now())); ps.setObject(4, Timestamp.from(now().plus(REFRESH_TTL))); ps.executeUpdate() }
        val playerId = connection.prepareStatement("SELECT player_id FROM identity.player_claim WHERE account_id = ? AND revoked_at IS NULL")
            .use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null } }
        return Session(accountId, playerId, access, refresh, accessExpires, created)
    }

    private fun revokeFamily(familyId: UUID, reason: String) {
        connection.prepareStatement("UPDATE identity.session_family SET revoked_at = ?, revoked_reason = ? WHERE family_id = ? AND revoked_at IS NULL")
            .use { ps -> ps.setObject(1, Timestamp.from(now())); ps.setString(2, reason); ps.setObject(3, familyId); ps.executeUpdate() }
    }

    private fun token(): String = ByteArray(32).also(random::nextBytes).let { Base64.getUrlEncoder().withoutPadding().encodeToString(it) }

    private fun <T> transaction(block: () -> T): T {
        if (!connection.autoCommit) return block()
        connection.autoCommit = false
        try {
            val r = block(); connection.commit(); return r
        } catch (e: Exception) {
            connection.rollback(); throw e
        } finally {
            connection.autoCommit = true
        }
    }

    internal fun sha256(s: String): ByteArray = MessageDigest.getInstance("SHA-256").digest(s.toByteArray(Charsets.UTF_8))
}
