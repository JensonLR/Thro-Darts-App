package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID
import thro.authz.ObjectRef
import thro.authz.ObjectType

/**
 * A fixture as one team lives it (PD-106): the opponent and the hour, who has said they can play, who has been
 * picked, and the match on THRØ it was played in.
 *
 * **Why this exists.** The league's side of a fixture — schedule, result, table — was complete, and the team's side
 * was only commands with nothing to read back: a captain could set availability and name a lineup over the wire and
 * never see either. And nothing outside a test ever cited a match to a fixture, so every league result was the
 * organiser's *declared* word even when the match had been scored on THRØ visit by visit. This closes both.
 */
public class TeamFixtures(private val connection: Connection) {

    public class Refused(public val why: String, public val status: Int) : Exception(why)

    public data class Member(val playerId: UUID, val name: String?, val role: String, val availability: String?, val availabilityVersion: Int)
    public data class View(
        val fixtureId: UUID, val leagueSeasonId: UUID, val teamId: UUID, val home: Boolean, val opponent: String?, val opponentTeamId: UUID,
        val scheduledAt: Instant, val state: String, val venue: String?, val version: Int, val matchId: UUID?,
        val yourRole: String, val mayNameLineup: Boolean, val members: List<Member>, val lineupVersion: Int, val lineup: List<UUID>,
    )

    private data class Row(val season: UUID, val home: UUID, val away: UUID, val at: Instant, val state: String, val venue: String?, val version: Int, val matchId: UUID?)

    private fun fixture(fixtureId: UUID): Row? =
        connection.prepareStatement(
            """SELECT f.league_season_id, f.home_team_id, f.away_team_id, f.scheduled_at, f.schedule_state, v.name, f.row_version, f.match_id
                 FROM competition.league_fixture f LEFT JOIN competition.venue v ON v.venue_id = f.venue_id AND v.visibility = 'public'
                WHERE f.fixture_id = ?""",
        ).use { ps ->
            ps.setObject(1, fixtureId)
            ps.executeQuery().use { rs ->
                if (!rs.next()) null
                else Row(rs.getObject(1) as UUID, rs.getObject(2) as UUID, rs.getObject(3) as UUID, rs.getTimestamp(4).toInstant(),
                         rs.getString(5), rs.getString(6), rs.getInt(7), rs.getObject(8) as UUID?)
            }
        }

    /** The fixture for [teamId], as [viewer] may read it: a member of that team, or nobody. */
    public fun view(fixtureId: UUID, teamId: UUID, viewer: UUID): View {
        val f = fixture(fixtureId) ?: throw Refused("THRØ has no such fixture.", 404)
        if (teamId != f.home && teamId != f.away) throw Refused("That team is not in this fixture.", 404)
        val role = Teams(connection).roleOf(viewer, teamId) ?: throw Refused("A team's fixture is for the team's own members.", 403)
        val opponentId = if (teamId == f.home) f.away else f.home
        val opponent = connection.prepareStatement("SELECT name FROM competition.team WHERE team_id = ? AND visibility = 'public'")
            .use { ps -> ps.setObject(1, opponentId); ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else null } }
        val orgs = Organisations(connection)
        val members = connection.prepareStatement(
            """SELECT m.player_id, m.role, (SELECT CASE WHEN identity.player_may_be_disclosed(m.player_id) AND a.display_name <> ? THEN a.display_name END
                                              FROM identity.player_claim c JOIN identity.account a ON a.account_id = c.account_id AND a.deleted_at IS NULL
                                             WHERE c.player_id = m.player_id AND c.revoked_at IS NULL)
                 FROM competition.team_membership m WHERE m.team_id = ? AND m.valid_until IS NULL
                ORDER BY m.valid_from, m.player_id""",
        ).use { ps ->
            ps.setString(1, Accounts.PLACEHOLDER_NAME); ps.setObject(2, teamId)
            ps.executeQuery().use { rs ->
                generateSequence {
                    if (!rs.next()) null else {
                        val player = rs.getObject(1) as UUID
                        val a = orgs.availabilityOf(fixtureId, player)
                        Member(player, rs.getString(3), rs.getString(2), a?.status?.name?.lowercase(), a?.version ?: 0)
                    }
                }.toList()
            }
        }
        val mayName = Relations(connection).decide(viewer, "team.manage", ObjectRef(ObjectType.TEAM, teamId.toString())).allowed
        return View(
            fixtureId, f.season, teamId, teamId == f.home, opponent, opponentId, f.at, f.state, f.venue, f.version, f.matchId,
            role, mayName, members, orgs.lineupVersion(fixtureId, teamId), orgs.currentLineup(fixtureId, teamId),
        )
    }

    /**
     * Names the match a fixture was played in, once. Only somebody who was *in* the match and runs one of the
     * fixture's teams may — the two things that make it their word to give — and the fixture's teams must be the ones
     * the match was between, which the caller's two roles together already say.
     */
    public fun cite(fixtureId: UUID, matchId: UUID, by: UUID) {
        val f = fixture(fixtureId) ?: throw Refused("THRØ has no such fixture.", 404)
        val match = Matches(connection).load(matchId) ?: throw Refused("THRØ has no such match.", 404)
        if (by !in match.participants) throw Refused("Only somebody who played the match may cite it.", 403)
        val rel = Relations(connection)
        val runsOne = listOf(f.home, f.away).any { rel.decide(by, "team.manage", ObjectRef(ObjectType.TEAM, it.toString())).allowed }
        if (!runsOne) throw Refused("Citing a match is for whoever runs one of the fixture's teams.", 403)
        if (f.matchId != null) throw Refused("This fixture already names its match. A fixture's match is not a field to point elsewhere.", 409)
        try { Organisations(connection).citeMatch(fixtureId, matchId) }
        catch (e: IllegalArgumentException) { throw Refused("This fixture already names its match.", 409) }
    }

    public fun json(v: View): String {
        val q = thro.api.http.Contract::q
        val members = v.members.joinToString(",") {
            """{"playerId":"${it.playerId}","name":${it.name?.let(q) ?: "null"},"availability":${it.availability?.let(q) ?: "null"},"availabilityVersion":${it.availabilityVersion},"role":${q(it.role)}}"""
        }
        return """{"fixtureId":"${v.fixtureId}","leagueSeasonId":"${v.leagueSeasonId}","teamId":"${v.teamId}","home":${v.home},""" +
            """"opponent":${v.opponent?.let(q) ?: "null"},"opponentTeamId":"${v.opponentTeamId}","scheduledAt":"${v.scheduledAt}","state":${q(v.state)},""" +
            """"venue":${v.venue?.let(q) ?: "null"},"version":${v.version},"matchId":${v.matchId?.let { "\"$it\"" } ?: "null"},""" +
            """"yourRole":${q(v.yourRole)},"mayNameLineup":${v.mayNameLineup},"members":[$members],""" +
            """"lineup":{"version":${v.lineupVersion},"players":[${v.lineup.joinToString(",") { "\"$it\"" }}]}}"""
    }
}
