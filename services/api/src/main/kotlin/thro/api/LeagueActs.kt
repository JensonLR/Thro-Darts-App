package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import thro.authz.ObjectRef
import thro.authz.ObjectType
import thro.competition.PointsPolicy

/**
 * The organiser's remaining acts over a league season (PD-112): the points rules a table is ordered by, moving a
 * team between divisions, and transferring a registered player to another team.
 *
 * Each is the season administrator's. Each is refused in words where the season's own facts forbid it — a team with
 * an undecided fixture in its division stays until that fixture is rearranged or voided, a transfer needs a current
 * registration and a team in the season. Each leaves the record it replaces in place: a superseded points policy, an
 * ended registration that the new one names as what it supersedes.
 */
public class LeagueActs(private val connection: Connection, private val now: () -> Instant = Instant::now) {

    public class Refused(public val why: String, public val status: Int) : Exception(why)

    private val london = ZoneId.of("Europe/London")
    private val rel get() = Relations(connection)

    private fun administers(by: UUID, season: UUID) {
        if (!Fixtures(connection).seasonExists(season)) throw Refused("THRØ has no such league season.", 404)
        if (!rel.decide(by, "league_season.administer", ObjectRef(ObjectType.LEAGUE_SEASON, season.toString())).allowed) throw Refused("You do not administer this league season.", 403)
    }

    // --- the points rules --------------------------------------------------------------------------------------------

    public data class Points(val policyId: UUID, val version: Int, val effectiveFrom: LocalDate, val policy: PointsPolicy, val says: String)

    /**
     * Sets the season's points rules: drafted and approved in one act, in force from today, superseding the season's
     * own previous rules from today (both in force for the day; the higher version is read). Read by the same strict
     * parser the table is ordered by, so a rule THRØ cannot execute is refused here rather than at the table.
     */
    public fun setPoints(season: UUID, by: UUID, win: Int?, draw: Int?, loss: Int?, awarded: Int?, perLegWon: Int?, tieBreak: List<String>?, awardsCountAsPlayed: Boolean?): Points {
        administers(by, season)
        val fields = LinkedHashMap<String, Any?>()
        win?.let { fields["win"] = it }; draw?.let { fields["draw"] = it }; loss?.let { fields["loss"] = it }; awarded?.let { fields["awarded"] = it }
        perLegWon?.let { fields["points_per_leg_won"] = it }; tieBreak?.let { fields["tie_break"] = it }; awardsCountAsPlayed?.let { fields["awards_count_as_played"] = it }
        val parsed = try { PointsPolicy.parse(fields) } catch (e: IllegalArgumentException) { throw Refused(e.message ?: "Those rules cannot be executed.", 400) }
        val pinned = connection.prepareStatement("SELECT standings_policy_id FROM competition.league_season WHERE league_season_id = ?")
            .use { ps -> ps.setObject(1, season); ps.executeQuery().use { rs -> rs.next(); rs.getObject(1) as UUID? } }
        if (pinned != null) throw Refused("This season's table is pinned to the rules it was played under; they are not changed after the fact.", 409)
        val today = now().atZone(london).toLocalDate()
        val orgs = Organisations(connection)
        val current = connection.prepareStatement(
            """SELECT policy_id FROM competition.policy WHERE authority_kind = 'league_season' AND league_season_id = ? AND kind = 'points'
                 AND approval_state = 'approved' AND effective_from <= ? AND (effective_to IS NULL OR effective_to >= ?) ORDER BY version DESC LIMIT 1""",
        ).use { ps -> ps.setObject(1, season); ps.setObject(2, today); ps.setObject(3, today); ps.executeQuery().use { rs -> if (rs.next()) rs.getObject(1) as UUID else null } }
        val version = (connection.prepareStatement("SELECT coalesce(max(version), 0) FROM competition.policy WHERE league_season_id = ? AND kind = 'points'")
            .use { ps -> ps.setObject(1, season); ps.executeQuery().use { rs -> rs.next(); rs.getInt(1) } }) + 1
        val q = thro.api.http.Contract::q
        val body = fields.entries.joinToString(",", "{", "}") { (k, v) ->
            q(k) + ":" + when (v) { is List<*> -> v.joinToString(",", "[", "]") { q(it.toString()) }; is Number, is Boolean -> v.toString(); else -> q(v.toString()) }
        }
        val wasAuto = connection.autoCommit
        connection.autoCommit = false
        try {
            if (current != null) orgs.supersedePolicy(current, today)
            val id = orgs.draftPolicy("league_season", season, "points", version, today, body, by = by)
            orgs.approvePolicy(id, by = by)
            connection.commit()
            return Points(id, version, today, parsed, says(parsed))
        } catch (e: Exception) { connection.rollback(); throw e } finally { connection.autoCommit = wasAuto }
    }

    private fun says(p: PointsPolicy): String {
        val head = "${p.win} ${if (p.win == 1) "point" else "points"} a win, ${p.draw} a draw"
        val leg = if (p.perLegWon > 0) ", and ${p.perLegWon} for every leg won" else ""
        return "$head$leg. This league's own rules."
    }

    // --- moving a team between divisions ------------------------------------------------------------------------------

    public data class Moved(val teamId: UUID, val divisionId: UUID?, val division: String?)

    public fun moveDivision(season: UUID, team: UUID, division: UUID?, by: UUID): Moved {
        administers(by, season)
        val name = division?.let {
            connection.prepareStatement("SELECT name FROM competition.division WHERE division_id = ? AND league_season_id = ?")
                .use { ps -> ps.setObject(1, it); ps.setObject(2, season); ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else null } }
                ?: throw Refused("That division is not one of this season's.", 400)
        }
        val current = connection.prepareStatement(
            "SELECT affiliation_id, division_id FROM competition.team_affiliation WHERE team_id = ? AND league_season_id = ? AND status = 'accepted' AND valid_until IS NULL",
        ).use { ps -> ps.setObject(1, team); ps.setObject(2, season); ps.executeQuery().use { rs -> if (rs.next()) (rs.getObject(1) as UUID) to (rs.getObject(2) as UUID?) else null } }
            ?: throw Refused("That team is not in this season.", 404)
        if (current.second == division) throw Refused("The team is already in ${name ?: "no division"}.", 409)
        val undecided = Fixtures(connection).of(season).count { (it.homeTeamId == team || it.awayTeamId == team) && it.decided == null && it.divisionId != division }
        if (undecided > 0) throw Refused("The team has $undecided undecided fixture${if (undecided == 1) "" else "s"} in its division; rearrange or void them before moving it.", 409)
        connection.prepareStatement("UPDATE competition.team_affiliation SET division_id = ? WHERE affiliation_id = ?")
            .use { ps -> ps.setObject(1, division); ps.setObject(2, current.first); ps.executeUpdate() }
        return Moved(team, division, name)
    }

    // --- transferring a registered player -------------------------------------------------------------------------------

    public data class Transferred(val playerId: UUID, val teamId: UUID, val team: String, val from: LocalDate, val registrationId: UUID, val supersedes: UUID)

    public fun transfer(season: UUID, player: UUID, toTeam: UUID, from: LocalDate, note: String?, by: UUID): Transferred {
        administers(by, season)
        if (note.isNullOrBlank()) throw Refused("A transfer says why.", 400)
        val team = connection.prepareStatement(
            "SELECT t.name FROM competition.team_affiliation a JOIN competition.team t ON t.team_id = a.team_id WHERE a.team_id = ? AND a.league_season_id = ? AND a.status = 'accepted' AND a.valid_until IS NULL",
        ).use { ps -> ps.setObject(1, toTeam); ps.setObject(2, season); ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else null } }
            ?: throw Refused("That team is not in this season.", 404)
        val at = from.atStartOfDay(london).toInstant()
        val current = connection.prepareStatement(
            """SELECT registration_id, team_id, policy_id FROM competition.player_registration
                WHERE player_id = ? AND league_season_id = ? AND status = 'registered' AND valid_from <= ? AND valid_until IS NULL ORDER BY valid_from DESC LIMIT 1""",
        ).use { ps -> ps.setObject(1, player); ps.setObject(2, season); ps.setObject(3, Timestamp.from(at)); ps.executeQuery().use { rs -> if (rs.next()) Triple(rs.getObject(1) as UUID, rs.getObject(2) as UUID?, rs.getObject(3) as UUID) else null } }
            ?: throw Refused("That player is not registered in this season on that date; a transfer moves a registration that exists.", 409)
        if (current.second == toTeam) throw Refused("The player is already registered with $team.", 409)
        val orgs = Organisations(connection)
        val wasAuto = connection.autoCommit
        connection.autoCommit = false
        try {
            orgs.endRegistration(current.first, at, reason = "transferred: ${note.trim().take(200)}")
            val id = orgs.register(player, season, toTeam, current.third, from = at, source = "organiser", by = by, supersedes = current.first)
            connection.commit()
            return Transferred(player, toTeam, team, from, id, current.first)
        } catch (e: Exception) { connection.rollback(); throw e } finally { connection.autoCommit = wasAuto }
    }

    // --- words --------------------------------------------------------------------------------------------------------------

    public fun json(p: Points): String {
        val q = thro.api.http.Contract::q
        return """{"points":{"policyId":"${p.policyId}","version":${p.version},"effectiveFrom":"${p.effectiveFrom}","win":${p.policy.win},"draw":${p.policy.draw},"loss":${p.policy.loss},""" +
            """"awarded":${p.policy.awarded},"pointsPerLegWon":${p.policy.perLegWon},"tieBreak":[${p.policy.chain.joinToString(",") { q(it.name.lowercase()) }}],""" +
            """"awardsCountAsPlayed":${p.policy.awardsCountAsPlayed},"says":${q(p.says)}}}"""
    }

    public fun json(m: Moved): String = """{"teamId":"${m.teamId}","divisionId":${m.divisionId?.let { "\"$it\"" } ?: "null"},"division":${m.division?.let(thro.api.http.Contract::q) ?: "null"}}"""

    public fun json(t: Transferred): String =
        """{"playerId":"${t.playerId}","teamId":"${t.teamId}","team":${thro.api.http.Contract.q(t.team)},"from":"${t.from}","registrationId":"${t.registrationId}","supersedes":"${t.supersedes}"}"""
}
