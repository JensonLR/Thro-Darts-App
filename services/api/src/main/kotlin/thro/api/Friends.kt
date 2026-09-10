package thro.api

import java.security.SecureRandom
import java.sql.Connection
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * Friends (V028): by code, in person, adults only, ended but never deleted.
 *
 * Refusals are answers, not exceptions: [Refused] carries the sentence the phone shows. The
 * database enforces the same rules by trigger, so a route that forgot one would be refused there.
 */
public class Friends(private val connection: Connection, private val now: () -> Instant = Instant::now) {

    public data class Invite(val code: String, val expiresAt: Instant)
    public data class Friend(val accountId: UUID, val displayName: String, val since: Instant)
    public class Refused(public val why: String) : Exception(why)

    public companion object {
        public val INVITE_TTL: Duration = Duration.ofDays(7)
        /** No 0/O/1/I: a code is said across a table. */
        private const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        private val random = SecureRandom()
        internal fun newCode(): String = (1..8).map { ALPHABET[random.nextInt(ALPHABET.length)] }.joinToString("")
        internal fun normalise(code: String): String = code.trim().uppercase().replace(" ", "").replace("-", "")
    }

    private fun band(accountId: UUID): String? =
        connection.prepareStatement("SELECT age_band FROM identity.account WHERE account_id = ? AND deleted_at IS NULL")
            .use { ps -> ps.setObject(1, accountId); ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else null } }

    private fun requireAdult(accountId: UUID) {
        when (band(accountId)) {
            "adult" -> Unit
            "minor" -> throw Refused("Friends on THRØ are for adults for now. A guardian's confirmation is coming.")
            else -> throw Refused("Say you are 18 or over under Account and profile first. THRØ does not guess ages.")
        }
    }

    /** A fresh code for this account, good for seven days. */
    public fun invite(accountId: UUID): Invite {
        requireAdult(accountId)
        val at = now()
        val expires = at.plus(INVITE_TTL)
        repeat(5) {
            val code = newCode()
            val inserted = connection.prepareStatement(
                "INSERT INTO identity.friend_invite (code, account_id, created_at, expires_at) VALUES (?, ?, ?, ?) ON CONFLICT (code) DO NOTHING",
            ).use { ps -> ps.setString(1, code); ps.setObject(2, accountId); ps.setTimestamp(3, Timestamp.from(at)); ps.setTimestamp(4, Timestamp.from(expires)); ps.executeUpdate() }
            if (inserted == 1) return Invite(code, expires)
        }
        error("could not mint a friend code")
    }

    /** Enters a code. Both become friends; the code is spent. */
    public fun accept(accountId: UUID, rawCode: String): Friend {
        requireAdult(accountId)
        val code = normalise(rawCode)
        if (!Regex("^[A-HJ-NP-Z2-9]{8}$").matches(code)) throw Refused("That is not a THRØ friend code: eight letters and numbers.")
        val at = now()
        val owner = connection.prepareStatement("SELECT account_id, expires_at, used_at FROM identity.friend_invite WHERE code = ? FOR UPDATE")
            .use { ps -> ps.setString(1, code); ps.executeQuery().use { rs -> if (rs.next()) Triple(rs.getObject(1) as UUID, rs.getTimestamp(2).toInstant(), rs.getTimestamp(3)?.toInstant()) else null } }
            ?: throw Refused("No friend code like that. Check it with the person who gave it to you.")
        if (owner.third != null) throw Refused("That code has been used already. Ask for a new one.")
        if (owner.second.isBefore(at)) throw Refused("That code has expired. Ask for a new one.")
        if (owner.first == accountId) throw Refused("That is your own code. Give it to a friend.")
        requireAdult(owner.first)
        val (a, b) = if (owner.first.toString() < accountId.toString()) owner.first to accountId else accountId to owner.first
        val already = connection.prepareStatement("SELECT 1 FROM identity.friendship WHERE account_a = ? AND account_b = ? AND ended_at IS NULL")
            .use { ps -> ps.setObject(1, a); ps.setObject(2, b); ps.executeQuery().use { it.next() } }
        if (already) throw Refused("You are friends already.")
        connection.prepareStatement("UPDATE identity.friend_invite SET used_by = ?, used_at = ? WHERE code = ?")
            .use { ps -> ps.setObject(1, accountId); ps.setTimestamp(2, Timestamp.from(at)); ps.setString(3, code); ps.executeUpdate() }
        connection.prepareStatement("INSERT INTO identity.friendship (friendship_id, account_a, account_b, created_at, invite_code) VALUES (?, ?, ?, ?, ?)")
            .use { ps -> ps.setObject(1, UUID.randomUUID()); ps.setObject(2, a); ps.setObject(3, b); ps.setTimestamp(4, Timestamp.from(at)); ps.setString(5, code); ps.executeUpdate() }
        return friends(accountId).first { it.accountId == owner.first }
    }

    /** Everyone this account is friends with, newest first. Display names only: a friend is someone who told you their name. */
    public fun friends(accountId: UUID): List<Friend> =
        connection.prepareStatement(
            """
            SELECT CASE WHEN f.account_a = ? THEN f.account_b ELSE f.account_a END AS other, a.display_name, f.created_at
              FROM identity.friendship f
              JOIN identity.account a ON a.account_id = CASE WHEN f.account_a = ? THEN f.account_b ELSE f.account_a END AND a.deleted_at IS NULL
             WHERE (f.account_a = ? OR f.account_b = ?) AND f.ended_at IS NULL
             ORDER BY f.created_at DESC
            """.trimIndent(),
        ).use { ps ->
            repeat(4) { ps.setObject(it + 1, accountId) }
            ps.executeQuery().use { rs -> generateSequence { if (rs.next()) Friend(rs.getObject(1) as UUID, rs.getString(2), rs.getTimestamp(3).toInstant()) else null }.toList() }
        }

    /** Ends a friendship from either side. True when there was one to end. */
    public fun remove(accountId: UUID, other: UUID): Boolean {
        val (a, b) = if (accountId.toString() < other.toString()) accountId to other else other to accountId
        return connection.prepareStatement("UPDATE identity.friendship SET ended_at = ?, ended_by = ? WHERE account_a = ? AND account_b = ? AND ended_at IS NULL")
            .use { ps -> ps.setTimestamp(1, Timestamp.from(now())); ps.setObject(2, accountId); ps.setObject(3, a); ps.setObject(4, b); ps.executeUpdate() == 1 }
    }

    /** The account says its own age band. Adult or minor, self-declared; never back to unknown. */
    public fun declareAge(accountId: UUID, band: String) {
        require(band == "adult" || band == "minor") { "ageBand is adult or minor" }
        val n = connection.prepareStatement("UPDATE identity.account SET age_band = ?, age_assurance = 'self_declared' WHERE account_id = ? AND deleted_at IS NULL")
            .use { ps -> ps.setString(1, band); ps.setObject(2, accountId); ps.executeUpdate() }
        require(n == 1) { "no such account" }
    }

    public fun json(friends: List<Friend>): String =
        "{\"friends\":[" + friends.joinToString(",") { """{"accountId":"${it.accountId}","displayName":${q(it.displayName)},"since":"${it.since}"}""" } + "]}"

    private fun q(s: String): String = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""
}
