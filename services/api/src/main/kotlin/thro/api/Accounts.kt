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
    /** A suspended account may not sign in (PD-103). Its sessions were revoked when it was suspended. */
    public class AccountSuspended : IllegalStateException("this account is suspended")

    /** A link was asked for, but the subject is already another account's. Nobody is signed in. */
    public class SubjectHeldElsewhere : IllegalStateException("that sign-in already belongs to another account")

    public sealed interface Refreshed {
        public data class Rotated(val session: Session) : Refreshed
        /** The token had been used before. The family is now revoked, and this says so. */
        public data object Reused : Refreshed
        public data object Unknown : Refreshed
        public data object Expired : Refreshed
    }

    /** [ways] is which kinds of way in the account holds — apple, google, passkey — so a phone can show them by name (PD-102).
     * [organiser] says whether this account may give a contact email (PD-104), and [contactEmail] is the one it gave. */
    public data class Profile(val accountId: UUID, val playerId: UUID?, val displayName: String, val ageBand: String, val named: Boolean, val credentials: Int,
                              val ways: List<String> = emptyList(), val organiser: Boolean = false, val contactEmail: String? = null)

    /** A contact email refused, in a sentence, with the status that says which kind of refusal (PD-104). */
    public class ContactRefused(public val why: String, public val status: Int) : IllegalStateException(why)

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
        if (linkTo != null && accountId != null && accountId != linkTo) throw SubjectHeldElsewhere()
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

    /** An account, its player and the claim binding them, in this transaction. [userHandle] when a passkey chose it first. */
    private fun newAccount(userHandle: ByteArray? = null): UUID {
        val accountId = UUID.randomUUID()
        // created_via 'self' makes V016's trigger record the person's own consent at creation.
        if (userHandle == null) {
            connection.prepareStatement("INSERT INTO identity.account (account_id, display_name, created_via) VALUES (?, ?, 'self')")
                .use { ps -> ps.setObject(1, accountId); ps.setString(2, PLACEHOLDER_NAME); ps.executeUpdate() }
        } else {
            connection.prepareStatement("INSERT INTO identity.account (account_id, display_name, created_via, user_handle) VALUES (?, ?, 'self', ?)")
                .use { ps -> ps.setObject(1, accountId); ps.setString(2, PLACEHOLDER_NAME); ps.setBytes(3, userHandle); ps.executeUpdate() }
        }
        val orgs = Organisations(connection)
        val playerId = orgs.createPlayer(source = "self", by = accountId)
        orgs.claim(playerId, accountId, method = "self_created")
        return accountId
    }

    // --- passkeys (V025) -----------------------------------------------------------------------

    public data class Challenge(val id: UUID, val bytes: ByteArray, val accountId: UUID?, val userHandle: ByteArray?)

    /**
     * A fresh ceremony: 32 random bytes, five minutes, once. [accountId] when a passkey is added to
     * an account. The device id is bookkeeping — it is whatever the caller said — not a control.
     */
    public fun newChallenge(kind: String, deviceId: UUID, accountId: UUID? = null): Challenge {
        // The sweep is told this clock's time and removes only what both clocks agree is a day expired
        // (V046). Reading the database's alone swept a live challenge whenever the two were a day apart.
        connection.prepareStatement("SELECT identity.sweep_challenges(?)").use { ps ->
            ps.setObject(1, Timestamp.from(now())); ps.executeQuery().close()
        }
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

    /** The WebAuthn user id for every passkey this account creates, and its live passkey ids to exclude. */
    public data class PasskeyIdentity(val userHandle: ByteArray, val credentialIds: List<ByteArray>)

    public fun passkeyIdentity(accountId: UUID): PasskeyIdentity? {
        val handle = connection.prepareStatement("SELECT user_handle FROM identity.account WHERE account_id = ? AND deleted_at IS NULL")
            .use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { rs -> if (rs.next()) rs.getBytes(1) else null } } ?: return null
        val ids = connection.prepareStatement("SELECT subject FROM identity.credential WHERE account_id = ? AND kind = 'passkey' AND revoked_at IS NULL")
            .use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { rs -> generateSequence { if (rs.next()) Base64.getUrlDecoder().decode(rs.getString(1)) else null }.toList() } }
        return PasskeyIdentity(handle, ids)
    }

    /** Stores a verified passkey — on [accountId], or on a new account with [userHandle] — and opens a session. */
    public fun registerPasskey(accountId: UUID?, userHandle: ByteArray?, credentialId: ByteArray, publicKeyCose: ByteArray, signCount: Long, deviceId: UUID): Session = transaction {
        val subject = Base64.getUrlEncoder().withoutPadding().encodeToString(credentialId)
        val account = accountId ?: newAccount(userHandle)
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
        // Every sign-in, by a provider or a passkey, mints its session here — so this is the one place a suspended
        // account is turned away (PD-103). Said in words at the door rather than by a session that dies on first use.
        if (isSuspended(accountId)) throw AccountSuspended()
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
              JOIN identity.account a ON a.account_id = t.account_id AND a.deleted_at IS NULL AND a.suspended_at IS NULL
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
            SELECT a.display_name, a.age_band, c.player_id, a.contact_email FROM identity.account a
              LEFT JOIN identity.player_claim c ON c.account_id = a.account_id AND c.revoked_at IS NULL
             WHERE a.account_id = ? AND a.deleted_at IS NULL
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, accountId)
            ps.executeQuery().use { rs ->
                if (!rs.next()) return null
                val player = rs.getObject(3) as UUID?
                val band = rs.getString(2)
                Profile(accountId, player, rs.getString(1), band, rs.getString(1) != PLACEHOLDER_NAME, credentialCount(accountId), waysIn(accountId),
                        organiser = band == "adult" && player != null && runsSomething(player), contactEmail = rs.getString(4))
            }
        }

    /** Whether this player holds a live admin relation on any league season or team — the shape of an organiser (PD-104). */
    public fun runsSomething(playerId: UUID): Boolean =
        connection.prepareStatement(
            "SELECT 1 FROM authz.relation WHERE subject_id = ? AND relation = 'admin' AND object_type IN ('league_season','team') AND revoked_at IS NULL LIMIT 1",
        ).use { ps -> ps.setObject(1, playerId); ps.executeQuery().use { it.next() } }

    /**
     * Gives, or takes away, the one piece of contact information THRØ holds (PD-104). Only an adult who runs a league
     * or a team may give one; anybody may take theirs away. Kept lower-case and trimmed; its shape is the database's
     * to hold, and a refusal there is answered here as a 400 rather than a fault.
     */
    public fun setContactEmail(accountId: UUID, email: String?) {
        val clean = email?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        if (clean != null) {
            val p = profile(accountId) ?: throw ContactRefused("no such account", 404)
            if (p.ageBand != "adult") throw ContactRefused("An email is given by an adult: say you are 18 or over first.", 403)
            if (p.playerId == null || !runsSomething(p.playerId)) throw ContactRefused("THRØ keeps an email only for somebody who runs a league or a team, so the teams in it can reach them.", 403)
            if (clean.length > 254 || !Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(clean)) throw ContactRefused("That does not look like an email address.", 400)
        }
        connection.prepareStatement("UPDATE identity.account SET contact_email = ?, contact_email_set_at = ? WHERE account_id = ? AND deleted_at IS NULL")
            .use { ps -> ps.setString(1, clean); ps.setObject(2, clean?.let { Timestamp.from(now()) }); ps.setObject(3, accountId); ps.executeUpdate() }
    }

    /** The contact emails of a season's administrators, for the people entitled to them (PD-104). */
    public fun organiserContacts(leagueSeasonId: UUID): List<String> =
        connection.prepareStatement(
            """
            SELECT DISTINCT a.contact_email
              FROM authz.relation r
              JOIN identity.player_claim c ON c.player_id = r.subject_id AND c.revoked_at IS NULL
              JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL AND a.suspended_at IS NULL
             WHERE r.relation = 'admin' AND r.object_type = 'league_season' AND r.object_id = ? AND r.revoked_at IS NULL
               AND a.contact_email IS NOT NULL
             ORDER BY a.contact_email
            """.trimIndent(),
        ).use { ps -> ps.setString(1, leagueSeasonId.toString()); ps.executeQuery().use { rs -> generateSequence { if (rs.next()) rs.getString(1) else null }.toList() } }

    /** Whether this player administers a team accepted, and still in, this season. */
    public fun runsATeamIn(playerId: UUID, leagueSeasonId: UUID): Boolean =
        connection.prepareStatement(
            """
            SELECT 1 FROM authz.relation r
              JOIN competition.team_affiliation ta ON ta.team_id::text = r.object_id AND ta.league_season_id = ?
                   AND ta.status = 'accepted' AND ta.valid_until IS NULL
             WHERE r.subject_id = ? AND r.relation = 'admin' AND r.object_type = 'team' AND r.revoked_at IS NULL
             LIMIT 1
            """.trimIndent(),
        ).use { ps -> ps.setObject(1, leagueSeasonId); ps.setObject(2, playerId); ps.executeQuery().use { it.next() } }

    /**
     * The kinds of way into an account that are live, each once (PD-102). A count alone left a person who had just added a
     * passkey looking at the same page — the sentence changed from two to three and nothing else did — so they could not
     * tell whether it had worked. The kind, never the credential or its subject: that is all a screen needs to name.
     */
    public fun waysIn(accountId: UUID): List<String> =
        connection.prepareStatement("SELECT DISTINCT kind FROM identity.credential WHERE account_id = ? AND revoked_at IS NULL ORDER BY kind")
            .use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { rs -> generateSequence { if (rs.next()) rs.getString(1) else null }.toList() } }

    public fun setDisplayName(accountId: UUID, name: String) {
        val trimmed = name.trim()
        require(trimmed.isNotEmpty() && trimmed.codePointCount(0, trimmed.length) <= 60) { "a display name is 1 to 60 characters" }
        require(trimmed.none { it.isISOControl() || it.category == CharCategory.FORMAT }) { "a display name has no control or formatting characters" }
        val n = connection.prepareStatement("UPDATE identity.account SET display_name = ? WHERE account_id = ? AND deleted_at IS NULL")
            .use { ps -> ps.setString(1, trimmed); ps.setObject(2, accountId); ps.executeUpdate() }
        require(n == 1) { "no such account" }
    }

    /**
     * What an erasure destroyed. Counts only — nothing here names anybody, which is the point.
     */
    public data class Erasure(
        val credentials: Int, val sessions: Int, val devices: Int,
        val friendships: Int, val claims: Int, val consents: Int,
    )

    /**
     * Take a person out of THRØ (V031).
     *
     * Everything that identifies them is destroyed: the name, the Apple or Google subject, every
     * passkey, every session on every device, the device labels, the live friendships, the claim on
     * their competitor row and the consent that let anything about them leave. What stays is what
     * belongs to other people — the matches they played, and the league and tournament rows those
     * results hold up — and after this those carry a competitor id that resolves to no person.
     *
     * The work is one `SECURITY DEFINER` function rather than statements here, because blanking a
     * credential's subject needs privileges this service must not hold the rest of the time.
     *
     * Refuses an account that is already erased, so a repeated tap cannot write a second erasure
     * row over the first one's counts.
     */
    public fun erase(accountId: UUID): Erasure = transaction {
        connection.prepareStatement(
            "SELECT credentials, sessions, devices, friendships, claims, consents FROM identity.erase_account(?)",
        ).use { ps ->
            ps.setObject(1, accountId)
            ps.executeQuery().use { rs ->
                check(rs.next()) { "erase_account returned nothing" }
                Erasure(rs.getInt(1), rs.getInt(2), rs.getInt(3), rs.getInt(4), rs.getInt(5), rs.getInt(6))
            }
        }
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

    public fun isSuspended(accountId: UUID): Boolean =
        connection.prepareStatement("SELECT 1 FROM identity.account WHERE account_id = ? AND suspended_at IS NOT NULL")
            .use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { it.next() } }

    /**
     * Suspends an account (PD-103): the hour and the reason on the row, and every live session family revoked, so the
     * person is signed out everywhere at once and `resolve` refuses whatever token they still hold. Suspending twice
     * changes nothing.
     */
    public fun suspend(accountId: UUID, reason: String) {
        val n = connection.prepareStatement(
            "UPDATE identity.account SET suspended_at = ?, suspended_reason = ? WHERE account_id = ? AND suspended_at IS NULL AND deleted_at IS NULL",
        ).use { ps -> ps.setObject(1, Timestamp.from(now())); ps.setString(2, reason); ps.setObject(3, accountId); ps.executeUpdate() }
        if (n == 0) return
        connection.prepareStatement("UPDATE identity.session_family SET revoked_at = ?, revoked_reason = ? WHERE account_id = ? AND revoked_at IS NULL")
            .use { ps -> ps.setObject(1, Timestamp.from(now())); ps.setString(2, "account suspended"); ps.setObject(3, accountId); ps.executeUpdate() }
    }

    /** Lifts a suspension. The sessions revoked by it stay revoked: the person signs in again. */
    public fun reinstate(accountId: UUID): Boolean =
        connection.prepareStatement("UPDATE identity.account SET suspended_at = NULL, suspended_reason = NULL WHERE account_id = ? AND suspended_at IS NOT NULL")
            .use { ps -> ps.setObject(1, accountId); ps.executeUpdate() } == 1

    /** Takes a name off an account (PD-103): back to the placeholder, which the person may change. */
    public fun hideName(accountId: UUID): Boolean =
        connection.prepareStatement("UPDATE identity.account SET display_name = ? WHERE account_id = ? AND deleted_at IS NULL")
            .use { ps -> ps.setString(1, PLACEHOLDER_NAME); ps.setObject(2, accountId); ps.executeUpdate() } == 1

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
