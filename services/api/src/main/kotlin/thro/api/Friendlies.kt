package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.Instant
import java.util.UUID
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * A friendly between two teams (PD-110): a game outside any season, proposed by whoever runs one team, answered by
 * whoever runs the other, and — once played on THRØ — naming the match it was played in, cited once by somebody who
 * played it and runs one of the teams.
 *
 * **Why its own table.** A league fixture is a season's row; a friendly is nobody's but the two teams'. V051 gives it
 * the shape of a rearrangement proposal (proposed, answered, the state says which) plus the one thing a fixture has
 * that a proposal does not: its match. Nothing here reaches a table or a rating.
 */
public class Friendlies(private val connection: Connection, private val now: () -> Instant = Instant::now) {

    public class Refused(public val why: String, public val status: Int) : Exception(why)

    private val rel get() = Relations(connection)
    private fun runsTeam(by: UUID, team: UUID) = rel.decide(by, "team.manage", ObjectRef(ObjectType.TEAM, team.toString())).allowed

    public data class Friendly(
        val friendlyId: UUID, val fromTeamId: UUID, val fromTeam: String, val toTeamId: UUID, val toTeam: String, val playAt: Instant,
        val venue: String?, val message: String?, val state: String, val proposedAt: Instant, val answeredAt: Instant?, val answerNote: String?,
        val matchId: UUID?, val version: Int,
    )

    private fun rows(where: String, vararg args: Any): List<Friendly> = connection.prepareStatement(
        """SELECT f.friendly_id, f.from_team_id, a.name, f.to_team_id, b.name, f.play_at, v.name, f.message, f.state, f.created_at, f.answered_at,
                  f.answer_note, f.match_id, f.row_version
             FROM competition.friendly f
             JOIN competition.team a ON a.team_id = f.from_team_id
             JOIN competition.team b ON b.team_id = f.to_team_id
             LEFT JOIN competition.venue v ON v.venue_id = f.venue_id AND v.visibility = 'public'
            WHERE $where ORDER BY f.play_at DESC, f.created_at DESC""",
    ).use { ps ->
        args.forEachIndexed { i, a -> ps.setObject(i + 1, a) }
        ps.executeQuery().use { rs ->
            generateSequence {
                if (!rs.next()) null
                else Friendly(rs.getObject(1) as UUID, rs.getObject(2) as UUID, rs.getString(3), rs.getObject(4) as UUID, rs.getString(5), rs.getTimestamp(6).toInstant(),
                              rs.getString(7), rs.getString(8), rs.getString(9), rs.getTimestamp(10).toInstant(), rs.getTimestamp(11)?.toInstant(),
                              rs.getString(12), rs.getObject(13) as UUID?, rs.getInt(14))
            }.toList()
        }
    }

    private fun one(id: UUID): Friendly = rows("f.friendly_id = ?", id).firstOrNull() ?: throw Refused("THRØ has no such friendly.", 404)

    private fun teamExists(teamId: UUID): Boolean =
        connection.prepareStatement("SELECT 1 FROM competition.team WHERE team_id = ? AND dissolved_at IS NULL")
            .use { ps -> ps.setObject(1, teamId); ps.executeQuery().use { it.next() } }

    // --- one team challenges another ---------------------------------------------------------------------------------

    public fun challenge(fromTeam: UUID, toTeam: UUID, playAt: Instant, message: String?, by: UUID): Friendly {
        if (!teamExists(fromTeam)) throw Refused("THRØ has no such team.", 404)
        if (!runsTeam(by, fromTeam)) throw Refused("Only whoever runs the team challenges on its behalf.", 403)
        if (fromTeam == toTeam) throw Refused("A team cannot challenge itself.", 400)
        if (!teamExists(toTeam)) throw Refused("THRØ has no such team to challenge.", 404)
        if (!playAt.isAfter(now())) throw Refused("The game is in the future.", 400)
        if (rows("f.state = 'proposed' AND least(f.from_team_id, f.to_team_id) = least(?::uuid, ?::uuid) AND greatest(f.from_team_id, f.to_team_id) = greatest(?::uuid, ?::uuid)", fromTeam, toTeam, fromTeam, toTeam).isNotEmpty()) {
            throw Refused("A challenge between these two teams is already waiting for an answer.", 409)
        }
        val id = UUID.randomUUID()
        try {
            connection.prepareStatement("INSERT INTO competition.friendly (friendly_id, from_team_id, to_team_id, play_at, message, proposed_by) VALUES (?, ?, ?, ?, ?, ?)").use { ps ->
                ps.setObject(1, id); ps.setObject(2, fromTeam); ps.setObject(3, toTeam); ps.setObject(4, Timestamp.from(playAt))
                ps.setString(5, message?.trim()?.takeIf { it.isNotEmpty() }?.take(280)); ps.setObject(6, by); ps.executeUpdate()
            }
        } catch (e: org.postgresql.util.PSQLException) { throw Refused("A challenge between these two teams is already waiting for an answer.", 409) }
        return one(id)
    }

    /** A team's friendlies, sent and received, for its members. */
    public fun ofTeam(teamId: UUID, viewer: UUID): List<Friendly> {
        if (!teamExists(teamId)) throw Refused("THRØ has no such team.", 404)
        if (Teams(connection).roleOf(viewer, teamId) == null) throw Refused("A team's friendlies are for its own members.", 403)
        return rows("f.from_team_id = ? OR f.to_team_id = ?", teamId, teamId)
    }

    // --- the other team answers; the challenger may withdraw --------------------------------------------------------

    public fun answer(id: UUID, answer: String, note: String?, by: UUID): Friendly {
        val f = one(id)
        if (!runsTeam(by, f.toTeamId)) throw Refused("Only whoever runs the challenged team answers.", 403)
        val state = when (answer) { "accepted" -> "accepted"; "declined", "rejected" -> "declined"; else -> throw Refused("An answer is accepted or declined.", 400) }
        if (state == "declined" && note.isNullOrBlank()) throw Refused("A refusal says why.", 400)
        if (f.state != "proposed") throw Refused("This challenge was already ${f.state}.", 409)
        val n = connection.prepareStatement("UPDATE competition.friendly SET state = ?, answered_by = ?, answered_at = clock_timestamp(), answer_note = ?, row_version = row_version + 1 WHERE friendly_id = ? AND state = 'proposed' AND row_version = ?")
            .use { ps -> ps.setString(1, state); ps.setObject(2, by); ps.setString(3, note?.trim()?.take(280)); ps.setObject(4, id); ps.setInt(5, f.version); ps.executeUpdate() }
        if (n == 0) throw Refused("This challenge was answered a moment ago.", 409)
        return one(id)
    }

    public fun withdraw(id: UUID, by: UUID): Friendly {
        val f = one(id)
        if (!runsTeam(by, f.fromTeamId)) throw Refused("Only whoever runs the challenging team withdraws it.", 403)
        if (f.state != "proposed") throw Refused("Only an unanswered challenge is withdrawn; this one was ${f.state}.", 409)
        connection.prepareStatement("UPDATE competition.friendly SET state = 'withdrawn', row_version = row_version + 1 WHERE friendly_id = ? AND state = 'proposed'")
            .use { ps -> ps.setObject(1, id); ps.executeUpdate() }
        return one(id)
    }

    // --- the match it was played in --------------------------------------------------------------------------------------

    /** Once, by somebody who played the match and runs one of the two teams — the same rule a league fixture keeps. */
    public fun cite(id: UUID, matchId: UUID, by: UUID): Friendly {
        val f = one(id)
        val match = Matches(connection).load(matchId) ?: throw Refused("THRØ has no such match.", 404)
        if (by !in match.participants) throw Refused("Only somebody who played the match may cite it.", 403)
        if (!runsTeam(by, f.fromTeamId) && !runsTeam(by, f.toTeamId)) throw Refused("Citing a match is for whoever runs one of the two teams.", 403)
        if (f.state != "accepted") throw Refused("Only an accepted friendly names its match; this one is ${f.state}.", 409)
        if (f.matchId != null) throw Refused("This friendly already names its match. It is not a field to point elsewhere.", 409)
        val n = try {
            connection.prepareStatement("UPDATE competition.friendly SET match_id = ?, row_version = row_version + 1 WHERE friendly_id = ? AND match_id IS NULL")
                .use { ps -> ps.setObject(1, matchId); ps.setObject(2, id); ps.executeUpdate() }
        } catch (e: org.postgresql.util.PSQLException) { throw Refused("That match already names another friendly.", 409) }
        if (n == 0) throw Refused("This friendly already names its match.", 409)
        return one(id)
    }

    // --- words -------------------------------------------------------------------------------------------------------------

    public fun json(f: Friendly, forTeam: UUID? = null): String {
        val q = thro.api.http.Contract::q
        val direction = forTeam?.let { if (it == f.fromTeamId) "sent" else "received" }
        return """{"friendlyId":"${f.friendlyId}","fromTeamId":"${f.fromTeamId}","fromTeam":${q(f.fromTeam)},"toTeamId":"${f.toTeamId}","toTeam":${q(f.toTeam)},""" +
            """"playAt":"${f.playAt}","venue":${f.venue?.let(q) ?: "null"},"message":${f.message?.let(q) ?: "null"},"state":${q(f.state)},""" +
            """"proposedAt":"${f.proposedAt}","answeredAt":${f.answeredAt?.let { "\"$it\"" } ?: "null"},"answerNote":${f.answerNote?.let(q) ?: "null"},""" +
            """"matchId":${f.matchId?.let { "\"$it\"" } ?: "null"},"version":${f.version},"direction":${direction?.let(q) ?: "null"}}"""
    }

    public fun json(list: List<Friendly>, forTeam: UUID): String = """{"friendlies":[${list.joinToString(",") { json(it, forTeam) }}]}"""
}
