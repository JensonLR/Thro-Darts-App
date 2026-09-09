package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.Instant
import java.util.UUID
import org.postgresql.util.PSQLException
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * Commands over organisational state (ADR-018): the second command family beside visits.
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
 *
 * A refusal the store makes itself — a non-member in a lineup, a lineup for a fixture already
 * played — is a [Result.Refused] in the store's own words, with a receipt, not an exception: the
 * write is rolled back to a savepoint so the receipt can still be recorded in the same transaction.
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

        /**
         * A player's word on a fixture, or a captain's on their behalf. [expectedVersion] is 0 for
         * the first word. Who said it is the actor, and the row keeps it.
         */
        public data class SetAvailability(
            override val commandId: UUID,
            override val deviceId: UUID,
            override val actorId: UUID,
            val fixtureId: UUID,
            val playerId: UUID,
            val teamId: UUID,
            val status: Organisations.Availability,
            val expectedVersion: Int,
            override val correlationId: UUID = UUID.randomUUID(),
        ) : Command

        /** The side a captain names, in slot order. [expectedVersion] is 0 for the first naming. */
        public data class NameLineup(
            override val commandId: UUID,
            override val deviceId: UUID,
            override val actorId: UUID,
            val fixtureId: UUID,
            val teamId: UUID,
            val players: List<UUID>,
            val expectedVersion: Int,
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
            // Authorise first, and record the decision whichever way it goes (ADR-008); only then
            // take the savepoint, so a refusal the store makes afterwards rolls back the attempt and
            // not the audit row.
            val denied = authorise(cmd)
            val result = if (denied != null) denied else {
                val savepoint = connection.setSavepoint()
                try {
                    apply(cmd)
                } catch (e: PSQLException) {
                    // The store said no in its own words (a trigger or check). Roll back to before
                    // the attempt so the refusal can be receipted in this transaction like any other.
                    if (e.sqlState != "23514") throw e
                    connection.rollback(savepoint)
                    Result.Refused(e.serverErrorMessage?.message ?: e.message ?: "refused by the store")
                }
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

    // --- authorise, then apply -----------------------------------------------------------------

    private fun authorise(cmd: Command): Result.Refused? = when (cmd) {
        is Command.RenameTeam -> {
            if (cmd.to.isBlank()) Result.Refused("a team needs a name")
            else decide(cmd.actorId, "team.manage", ObjectRef(ObjectType.TEAM, cmd.teamId.toString()), cmd.correlationId, "you do not run this team")
        }
        is Command.RearrangeFixture -> {
            val season = seasonOf(cmd.fixtureId)
            if (season == null) Result.Refused("no such fixture")
            else decide(cmd.actorId, "league_fixture.rearrange", ObjectRef(ObjectType.LEAGUE_SEASON, season), cmd.correlationId, "you do not administer this league season")
        }
        is Command.SetAvailability -> {
            // The player's own word needs no relation; anyone else needs to run the team, and the
            // row then says it was them — the provenance "on their behalf" requires. The actor id
            // here is the player's THRØ ID; when actors become accounts (FB-1) the API boundary maps
            // an account to its live claim before this point (plan §5).
            if (cmd.actorId == cmd.playerId) null
            else decide(cmd.actorId, "team.manage", ObjectRef(ObjectType.TEAM, cmd.teamId.toString()), cmd.correlationId,
                "only the player, or someone who runs their team, records their availability")
        }
        is Command.NameLineup -> {
            if (cmd.players.isEmpty()) Result.Refused("a lineup names at least one player")
            else if (cmd.players.toSet().size != cmd.players.size) Result.Refused("a player is named once in a lineup")
            else decide(cmd.actorId, "team.manage", ObjectRef(ObjectType.TEAM, cmd.teamId.toString()), cmd.correlationId, "you do not run this team")
        }
    }

    private fun decide(actor: UUID, action: String, obj: ObjectRef, correlation: UUID, why: String): Result.Refused? {
        val decision = Relations(connection).decide(actor, action, obj, correlation)
        return if (decision.allowed) null else Result.Refused(why, decision.excludedBy)
    }

    private fun apply(cmd: Command): Result = when (cmd) {
        is Command.RenameTeam -> renameTeam(cmd)
        is Command.RearrangeFixture -> rearrangeFixture(cmd)
        is Command.SetAvailability -> setAvailability(cmd)
        is Command.NameLineup -> nameLineup(cmd)
    }

    private fun renameTeam(cmd: Command.RenameTeam): Result {
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

    private fun setAvailability(cmd: Command.SetAvailability): Result {
        val orgs = Organisations(connection)
        val current = orgs.availabilityOf(cmd.fixtureId, cmd.playerId)
        val version = current?.version ?: 0
        if (version != cmd.expectedVersion) return Result.Stale(version, availabilityJson(cmd.fixtureId, cmd.playerId))
        val applied = orgs.recordAvailability(cmd.fixtureId, cmd.playerId, cmd.teamId, cmd.status, cmd.actorId, cmd.expectedVersion)
            ?: return Result.Stale(orgs.availabilityOf(cmd.fixtureId, cmd.playerId)?.version ?: 0, availabilityJson(cmd.fixtureId, cmd.playerId))
        return Result.Applied(applied)
    }

    private fun nameLineup(cmd: Command.NameLineup): Result {
        val orgs = Organisations(connection)
        val version = orgs.lineupVersion(cmd.fixtureId, cmd.teamId)
        if (version != cmd.expectedVersion) return Result.Stale(version, lineupJson(cmd.fixtureId, cmd.teamId))
        val applied = orgs.nameLineup(cmd.fixtureId, cmd.teamId, cmd.players, cmd.actorId, cmd.expectedVersion)
            ?: return Result.Stale(orgs.lineupVersion(cmd.fixtureId, cmd.teamId), lineupJson(cmd.fixtureId, cmd.teamId))
        return Result.Applied(applied)
    }

    // --- reads ----------------------------------------------------------------------------------

    private fun availabilityJson(fixtureId: UUID, playerId: UUID): String =
        connection.prepareStatement("SELECT coalesce(to_jsonb(a)::text, 'null') FROM competition.availability a WHERE fixture_id = ? AND player_id = ?").use { ps ->
            ps.setObject(1, fixtureId); ps.setObject(2, playerId)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else "null" }
        }

    private fun lineupJson(fixtureId: UUID, teamId: UUID): String =
        connection.prepareStatement(
            """
            SELECT coalesce((SELECT to_jsonb(l) || jsonb_build_object('players', coalesce((SELECT jsonb_agg(player_id ORDER BY slot) FROM competition.current_lineup(l.fixture_id, l.team_id)), '[]'::jsonb))
                               FROM competition.lineup l WHERE fixture_id = ? AND team_id = ?)::text, 'null')
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, fixtureId); ps.setObject(2, teamId)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else "null" }
        }

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
