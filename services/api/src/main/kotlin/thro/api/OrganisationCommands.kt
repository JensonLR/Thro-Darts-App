package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.Instant
import java.util.UUID
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * Commands over organisational state (ADR-017): the second command family beside visits.
 *
 * A visit is evidence and travels as a per-device append-only stream. A team's name or a fixture's
 * date is a server-authoritative row with a version. The rule here is the one the founder's brief
 * makes non-negotiable — a later write from another phone must never silently replace what another
 * admin did:
 *
 * 1. **Receipt first.** A replay returns the stored response verbatim, including a refusal or a
 *    stale-version response, and applies nothing (ADR-006 step 1, for this kind of state).
 * 2. **Authorise** at the one decision point, and record the decision whichever way it goes.
 * 3. **Apply with the version the author saw.** Zero rows updated is [Result.Stale], carrying the
 *    current row so the person can see what changed under them. Never merged. Never overwritten.
 * 4. **Receipt in the same transaction** as the change, or there is no change.
 */
public class OrganisationCommands(private val connection: Connection) {

    /** What a client sends. Every command names its author, its device and the version it saw. */
    public sealed interface Command {
        public val commandId: UUID
        public val deviceId: UUID
        public val actorId: UUID
        public val correlationId: UUID

        public data class RenameTeam(
            override val commandId: UUID,
            override val deviceId: UUID,
            override val actorId: UUID,
            val teamId: UUID,
            val to: String,
            val expectedVersion: Int,
            override val correlationId: UUID = UUID.randomUUID(),
        ) : Command

        public data class RearrangeFixture(
            override val commandId: UUID,
            override val deviceId: UUID,
            override val actorId: UUID,
            val fixtureId: UUID,
            val to: Instant,
            val expectedVersion: Int,
            val venueId: UUID? = null,
            override val correlationId: UUID = UUID.randomUUID(),
        ) : Command
    }

    public sealed interface Result {
        /** The change was made; the row is now at [version]. */
        public data class Applied(val version: Int) : Result

        /** Not permitted, or not possible. Nothing changed. */
        public data class Refused(val why: String, val excludedBy: String? = null) : Result

        /**
         * Somebody else changed the row after this author last saw it. Nothing changed. [current]
         * is the row as it stands, for the person to decide against — never for the client to
         * retry blindly.
         */
        public data class Stale(val currentVersion: Int, val current: String) : Result

        /** A replay. The stored response is returned verbatim, whatever it was. */
        public data class Replayed(val stored: String) : Result
    }

    public fun handle(cmd: Command): Result {
        val previousAutoCommit = connection.autoCommit
        connection.autoCommit = false
        try {
            storedReceipt(cmd)?.let {
                connection.commit()
                return Result.Replayed(it)
            }
            val result = when (cmd) {
                is Command.RenameTeam -> renameTeam(cmd)
                is Command.RearrangeFixture -> rearrangeFixture(cmd)
            }
            writeReceipt(cmd, result)
            connection.commit()
            return result
        } catch (e: Exception) {
            connection.rollback()
            throw e
        } finally {
            connection.autoCommit = previousAutoCommit
        }
    }

    // --- the two commands ---------------------------------------------------------------------

    private fun renameTeam(cmd: Command.RenameTeam): Result {
        if (cmd.to.isBlank()) return Result.Refused("a team needs a name")
        val decision = Relations(connection).decide(
            cmd.actorId, "team.manage", ObjectRef(ObjectType.TEAM, cmd.teamId.toString()), cmd.correlationId,
        )
        if (!decision.allowed) {
            return Result.Refused("you do not run this team", decision.excludedBy)
        }
        val current = currentTeam(cmd.teamId) ?: return Result.Refused("no such team")
        if (current.first != cmd.expectedVersion) {
            return Result.Stale(current.first, current.second)
        }
        // The version check is repeated in the statement itself, because between the read above
        // and this write another writer may have committed. The trigger on the row refuses any
        // version that is not exactly old + 1, so the guard holds even outside this handler.
        val n = connection.prepareStatement(
            "UPDATE competition.team SET name = ?, row_version = ? WHERE team_id = ? AND row_version = ?",
        ).use { ps ->
            ps.setString(1, cmd.to); ps.setInt(2, cmd.expectedVersion + 1)
            ps.setObject(3, cmd.teamId); ps.setInt(4, cmd.expectedVersion)
            ps.executeUpdate()
        }
        if (n == 0) {
            val now = currentTeam(cmd.teamId) ?: return Result.Refused("no such team")
            return Result.Stale(now.first, now.second)
        }
        return Result.Applied(cmd.expectedVersion + 1)
    }

    private fun rearrangeFixture(cmd: Command.RearrangeFixture): Result {
        val decision = Relations(connection).decide(
            cmd.actorId, "league_fixture.rearrange",
            ObjectRef(ObjectType.LEAGUE_SEASON, seasonOf(cmd.fixtureId) ?: return Result.Refused("no such fixture")),
            cmd.correlationId,
        )
        if (!decision.allowed) {
            return Result.Refused("you do not administer this league season", decision.excludedBy)
        }
        val current = currentFixture(cmd.fixtureId) ?: return Result.Refused("no such fixture")
        if (current.first != cmd.expectedVersion) {
            return Result.Stale(current.first, current.second)
        }
        val n = connection.prepareStatement(
            """
            UPDATE competition.league_fixture
               SET scheduled_at = ?, venue_id = coalesce(?, venue_id), schedule_state = 'rearranged', row_version = ?
             WHERE fixture_id = ? AND row_version = ?
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, Timestamp.from(cmd.to)); ps.setObject(2, cmd.venueId)
            ps.setInt(3, cmd.expectedVersion + 1); ps.setObject(4, cmd.fixtureId); ps.setInt(5, cmd.expectedVersion)
            ps.executeUpdate()
        }
        if (n == 0) {
            val now = currentFixture(cmd.fixtureId) ?: return Result.Refused("no such fixture")
            return Result.Stale(now.first, now.second)
        }
        return Result.Applied(cmd.expectedVersion + 1)
    }

    // --- reads ----------------------------------------------------------------------------------

    /** (version, row as JSON) — the JSON is what a Stale response hands back to the person. */
    private fun currentTeam(teamId: UUID): Pair<Int, String>? =
        connection.prepareStatement(
            "SELECT row_version, to_jsonb(t)::text FROM competition.team t WHERE team_id = ?",
        ).use { ps ->
            ps.setObject(1, teamId)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getInt(1) to rs.getString(2) else null }
        }

    private fun currentFixture(fixtureId: UUID): Pair<Int, String>? =
        connection.prepareStatement(
            "SELECT row_version, to_jsonb(f)::text FROM competition.league_fixture f WHERE fixture_id = ?",
        ).use { ps ->
            ps.setObject(1, fixtureId)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getInt(1) to rs.getString(2) else null }
        }

    private fun seasonOf(fixtureId: UUID): String? =
        connection.prepareStatement(
            "SELECT league_season_id FROM competition.league_fixture WHERE fixture_id = ?",
        ).use { ps ->
            ps.setObject(1, fixtureId)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else null }
        }

    // --- receipts -------------------------------------------------------------------------------

    private fun storedReceipt(cmd: Command): String? =
        connection.prepareStatement(
            "SELECT response_body::text FROM competition.command_receipt WHERE device_id = ? AND client_command_id = ?",
        ).use { ps ->
            ps.setObject(1, cmd.deviceId); ps.setObject(2, cmd.commandId)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else null }
        }

    private fun writeReceipt(cmd: Command, result: Result) {
        val (outcome, reason, body) = when (result) {
            is Result.Applied -> Triple("applied", null, """{"outcome":"applied","version":${result.version}}""")
            is Result.Refused -> Triple("refused", result.why, """{"outcome":"refused","why":${json(result.why)}}""")
            is Result.Stale -> Triple("stale", "stale_version", """{"outcome":"stale","currentVersion":${result.currentVersion},"current":${result.current}}""")
            is Result.Replayed -> error("a replay is never written as a new receipt")
        }
        connection.prepareStatement(
            """
            INSERT INTO competition.command_receipt
              (device_id, client_command_id, command_type, outcome, reason_code, response_body)
            VALUES (?, ?, ?, ?, ?, ?::jsonb)
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, cmd.deviceId); ps.setObject(2, cmd.commandId)
            ps.setString(3, cmd::class.simpleName); ps.setString(4, outcome); ps.setString(5, reason)
            ps.setString(6, body)
            ps.executeUpdate()
        }
    }

    private fun json(s: String): String = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
}
