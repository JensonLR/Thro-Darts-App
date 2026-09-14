package thro.api

import java.sql.Connection
import java.sql.Timestamp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeParseException
import java.util.UUID

/**
 * What running a league season needs before any result can go in: the teams that asked to be in it, and its
 * fixtures (PD-099).
 *
 * **Nothing could create a fixture before this.** `Organisations.scheduleFixture` existed and no route reached it,
 * so a season came in from the directory with its teams waiting at the door and not one fixture — and every surface
 * built on fixtures (the result entry, the table, the live board, the television) had nothing to show.
 *
 * The rules a fixture is held to are the ones a table already assumes. The tallies count a fixture only when both
 * sides are accepted into the season (V041), so scheduling one against a team still waiting would make a match that
 * counts for nobody; that is refused here rather than discovered when the table comes out empty.
 */
public class SeasonPlanning(private val connection: Connection) {

    /** A plan refused, with the status that says which kind of refusal and a sentence an organiser can act on. */
    public class Refused(public val status: Int, public val why: String) : RuntimeException(why)

    public data class Division(val divisionId: UUID, val name: String, val ordinal: Int)
    public data class Entrant(val affiliationId: UUID, val teamId: UUID, val name: String, val divisionId: UUID?, val status: String)
    public data class Season(
        val leagueSeasonId: UUID, val label: String, val startsOn: LocalDate, val endsOn: LocalDate,
        val divisions: List<Division>, val teams: List<Entrant>,
    )
    public data class Wanted(val homeTeamId: UUID, val awayTeamId: UUID, val scheduledAt: Instant, val divisionId: UUID?)
    public data class Scheduled(val fixtureId: UUID, val wanted: Wanted, val divisionId: UUID?)

    public companion object {
        /** A season's worth and then some: forty teams playing each other home and away is 1,560, but a division
         * is rarely more than twelve, and a list longer than this is more likely a mistake than a league. */
        public const val MOST: Int = 400

        /** The day a fixture falls on is the day in the UK, where the leagues are, not the day in UTC. */
        private val LEAGUE_TIME: ZoneId = ZoneId.of("Europe/London")

        /** The request, read strictly: anything of the wrong shape is a 400 before any row is looked at. */
        public fun parse(body: Map<String, Any?>): List<Wanted> {
            val list = body["fixtures"] as? List<*>
                ?: throw IllegalArgumentException("A season's fixtures are a list: send them as `fixtures`.")
            require(list.isNotEmpty()) { "There are no fixtures in that list." }
            require(list.size <= MOST) { "That is more than $MOST fixtures at once. Send the season a division at a time." }
            return list.mapIndexed { i, raw ->
                val n = i + 1
                val m = raw as? Map<*, *> ?: throw IllegalArgumentException("Fixture $n is not a fixture.")
                fun uuid(key: String, optional: Boolean = false): UUID? {
                    val v = m[key] ?: if (optional) return null else throw IllegalArgumentException("Fixture $n has no $key.")
                    return try { UUID.fromString(v as? String ?: throw IllegalArgumentException()) }
                           catch (e: IllegalArgumentException) { throw IllegalArgumentException("Fixture $n: $key is not a UUID.") }
                }
                val at = try { Instant.parse(m["scheduledAt"] as? String ?: throw IllegalArgumentException()) }
                         catch (e: IllegalArgumentException) { throw IllegalArgumentException("Fixture $n has no scheduledAt, or it is not a date and time.") }
                         catch (e: DateTimeParseException) { throw IllegalArgumentException("Fixture $n: scheduledAt is not a date and time.") }
                Wanted(uuid("homeTeamId")!!, uuid("awayTeamId")!!, at, uuid("divisionId", optional = true))
            }
        }
    }

    public fun season(id: UUID): Season? {
        val head = connection.prepareStatement(
            "SELECT label, starts_on, ends_on FROM competition.league_season WHERE league_season_id = ?",
        ).use { ps ->
            ps.setObject(1, id)
            ps.executeQuery().use { rs -> if (!rs.next()) return null else Triple(rs.getString(1), rs.getObject(2, LocalDate::class.java), rs.getObject(3, LocalDate::class.java)) }
        }
        val divisions = connection.prepareStatement(
            "SELECT division_id, name, ordinal FROM competition.division WHERE league_season_id = ? ORDER BY ordinal",
        ).use { ps ->
            ps.setObject(1, id)
            ps.executeQuery().use { rs -> generateSequence { if (rs.next()) Division(rs.getObject(1) as UUID, rs.getString(2), rs.getInt(3)) else null }.toList() }
        }
        // The open affiliation only: a team that left the season is not in it, whatever it once was.
        val teams = connection.prepareStatement(
            """
            SELECT a.affiliation_id, a.team_id, t.name, a.division_id, a.status
              FROM competition.team_affiliation a
              JOIN competition.team t ON t.team_id = a.team_id
             WHERE a.league_season_id = ? AND a.valid_until IS NULL
             ORDER BY a.status DESC, t.name, a.team_id
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, id)
            ps.executeQuery().use { rs ->
                generateSequence {
                    if (rs.next()) Entrant(rs.getObject(1) as UUID, rs.getObject(2) as UUID, rs.getString(3), rs.getObject(4) as UUID?, rs.getString(5)) else null
                }.toList()
            }
        }
        return Season(id, head.first, head.second, head.third, divisions, teams)
    }

    /**
     * Every fixture checked before any is written, then all of them in one transaction: a list that half went in
     * would leave an organiser working out which half, and a season with half its fixtures is wrong in a way the
     * table does not show.
     */
    public fun schedule(leagueSeasonId: UUID, wanted: List<Wanted>, by: UUID?): List<Scheduled> {
        val season = season(leagueSeasonId) ?: throw Refused(404, "THRØ has no such league season.")
        val entrants = season.teams.associateBy { it.teamId }
        val divisions = season.divisions.associateBy { it.divisionId }
        val seen = HashSet<Triple<UUID, UUID, Instant>>()
        val busy = HashSet<Pair<UUID, Instant>>()

        val plan = wanted.mapIndexed { i, w ->
            val n = i + 1
            fun refuse(why: String): Nothing = throw Refused(422, "Fixture $n: $why")
            if (w.homeTeamId == w.awayTeamId) refuse("a team cannot play itself.")
            val home = entrants[w.homeTeamId] ?: refuse("${nameOf(w.homeTeamId)} has not asked to be in this season.")
            val away = entrants[w.awayTeamId] ?: refuse("${nameOf(w.awayTeamId)} has not asked to be in this season.")
            for (side in listOf(home, away)) {
                if (side.status != "accepted") refuse("${side.name} is still waiting to be let into the season. Accept it first.")
            }
            val day = w.scheduledAt.atZone(LEAGUE_TIME).toLocalDate()
            if (day.isBefore(season.startsOn) || day.isAfter(season.endsOn)) {
                refuse("${home.name} v ${away.name} is on $day, outside the season (${season.startsOn} to ${season.endsOn}).")
            }
            if (home.divisionId != away.divisionId) {
                refuse("${home.name} and ${away.name} are in different divisions, so they do not meet in the league.")
            }
            val division = w.divisionId ?: home.divisionId
            if (division != home.divisionId) {
                val named = divisions[division]?.name ?: "that division"
                refuse("neither ${home.name} nor ${away.name} is in $named.")
            }
            if (!seen.add(Triple(w.homeTeamId, w.awayTeamId, w.scheduledAt))) {
                refuse("${home.name} v ${away.name} at ${w.scheduledAt} is in this list twice.")
            }
            // A team plays one match at a time. Checked within the list; a fixture already standing at the same
            // moment is the organiser's to rearrange, and refusing it here would block entering a known clash.
            for (side in listOf(home, away)) {
                if (!busy.add(side.teamId to w.scheduledAt)) refuse("${side.name} would be playing twice at ${w.scheduledAt}.")
            }
            if (alreadyScheduled(leagueSeasonId, w)) {
                throw Refused(409, "Fixture $n: ${home.name} v ${away.name} at ${w.scheduledAt} is already scheduled.")
            }
            w to division
        }

        val orgs = Organisations(connection)
        val wasAuto = connection.autoCommit
        connection.autoCommit = false
        try {
            val made = plan.map { (w, division) ->
                Scheduled(orgs.scheduleFixture(leagueSeasonId, division, w.homeTeamId, w.awayTeamId, w.scheduledAt, by = by), w, division)
            }
            connection.commit()
            return made
        } catch (e: Exception) {
            connection.rollback()
            throw e
        } finally {
            connection.autoCommit = wasAuto
        }
    }

    private fun nameOf(teamId: UUID): String =
        connection.prepareStatement("SELECT name FROM competition.team WHERE team_id = ?").use { ps ->
            ps.setObject(1, teamId)
            ps.executeQuery().use { rs -> if (rs.next()) rs.getString(1) else "A team THRØ has no record of" }
        }

    private fun alreadyScheduled(leagueSeasonId: UUID, w: Wanted): Boolean =
        connection.prepareStatement(
            """SELECT 1 FROM competition.league_fixture
                WHERE league_season_id = ? AND home_team_id = ? AND away_team_id = ? AND scheduled_at = ?""",
        ).use { ps ->
            ps.setObject(1, leagueSeasonId); ps.setObject(2, w.homeTeamId); ps.setObject(3, w.awayTeamId)
            ps.setObject(4, Timestamp.from(w.scheduledAt))
            ps.executeQuery().use { it.next() }
        }

    public fun json(s: Season): String {
        fun q(v: String?) = v?.let { thro.api.http.Contract.q(it) } ?: "null"
        val divisions = s.divisions.joinToString(",") { """{"divisionId":"${it.divisionId}","name":${q(it.name)},"ordinal":${it.ordinal}}""" }
        val teams = s.teams.joinToString(",") {
            """{"affiliationId":"${it.affiliationId}","teamId":"${it.teamId}","name":${q(it.name)},"divisionId":${it.divisionId?.let { d -> "\"$d\"" } ?: "null"},"status":${q(it.status)}}"""
        }
        return """{"leagueSeasonId":"${s.leagueSeasonId}","label":${q(s.label)},"startsOn":"${s.startsOn}","endsOn":"${s.endsOn}","divisions":[$divisions],"teams":[$teams]}"""
    }

    public fun json(made: List<Scheduled>): String =
        """{"created":[""" + made.joinToString(",") {
            """{"fixtureId":"${it.fixtureId}","homeTeamId":"${it.wanted.homeTeamId}","awayTeamId":"${it.wanted.awayTeamId}","scheduledAt":"${it.wanted.scheduledAt}","divisionId":${it.divisionId?.let { d -> "\"$d\"" } ?: "null"}}"""
        } + "]}"
}
