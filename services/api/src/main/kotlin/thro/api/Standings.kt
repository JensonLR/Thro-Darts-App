package thro.api

import java.sql.Connection
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import thro.competition.PointsPolicy
import thro.competition.StandingsRow
import thro.competition.TieBreak
import thro.competition.Standings as Ranker

/**
 * A league's table (PD-054, V041).
 *
 * **Computed on every read and stored nowhere.** `OrganisationTest` holds that no table in `competition` has
 * "standing" in its name, and this is why: a table that is arithmetic over the fixtures beneath it cannot
 * drift from them, cannot be edited into disagreeing with them, and cannot be left stale by a corrected
 * result. V041's `league_tallies` counts; this applies the league's rules to the counts and orders the rows.
 *
 * **The rules are the league's, and the table says whose they are.** A league with an approved `points`
 * policy is ordered by it. A league with none is ordered by THRØ's standard — two a win, one a draw — and
 * every table names which of those it was, because a standard nobody can see is a standard THRØ imposed.
 * That is the condition PD-054 was decided under.
 *
 * **Only the teams the league affiliated.** A team that says it plays in a league (PD-049) is a team
 * speaking about itself, and is never a row here. V041 reads `team_affiliation` alone, so this holds
 * structurally rather than by a filter anybody could forget to write.
 */
public class LeagueTable(private val connection: Connection) {

    public data class Row(
        val teamId: UUID, val name: String, val position: Int,
        /** Which step of the declared chain put this row above the one below, or null when nothing could. */
        val separatedBy: String?,
        val played: Int, val won: Int, val drawn: Int, val lost: Int,
        val legsFor: Int, val legsAgainst: Int, val legDifference: Int, val points: Int,
        val awardedFor: Int, val awardedAgainst: Int,
        /** How many of the played fixtures cite a match scored on THRØ rather than somebody's word (PD-020). */
        val evidenced: Int,
    )

    public data class Division(
        val divisionId: UUID?, val name: String, val ordinal: Int?,
        /** Fixtures whose date has passed with no result entered. A table missing results is quietly wrong. */
        val awaitingResults: Int,
        val rows: List<Row>,
    )

    /** Which rules ordered the table, and whose they are. Never absent from an answer. */
    public data class Rules(
        val policyId: UUID?, val version: Int?, val mine: Boolean, val says: String, val orderedBy: List<String>,
    )

    public data class Table(
        val leagueSeasonId: UUID, val leagueId: UUID, val league: String, val label: String, val state: String,
        val rules: Rules, val divisions: List<Division>,
    )

    public class Refused(public val why: String, public val status: Int) : Exception(why)

    /** The season's table, by division; [division] narrows it to one. */
    public fun of(leagueSeasonId: UUID, division: UUID? = null, now: Instant): Table {
        val season = season(leagueSeasonId) ?: throw Refused("THRØ has no such league season.", 404)
        val (policy, rules) = rules(leagueSeasonId, season, now)
        val divisions = divisions(leagueSeasonId, division).ifEmpty {
            // A season may run undivided; its fixtures then carry no division and the season is the table.
            listOf(Triple(null as UUID?, season.label, null as Int?))
        }
        return Table(
            leagueSeasonId, season.leagueId, season.league, season.label, season.state, rules,
            divisions.map { (id, name, ordinal) ->
                Division(id, name, ordinal, awaiting(leagueSeasonId, id, now), rank(leagueSeasonId, id, policy))
            },
        )
    }

    private class Season(val leagueId: UUID, val league: String, val label: String, val state: String,
                         val pinned: UUID?)

    private fun season(id: UUID): Season? =
        connection.prepareStatement(
            """SELECT ls.league_id, l.name, ls.label, ls.state, ls.standings_policy_id
                 FROM competition.league_season ls
                 JOIN competition.league l ON l.league_id = ls.league_id
                WHERE ls.league_season_id = ?""",
        ).use { ps ->
            ps.setObject(1, id)
            ps.executeQuery().use { rs ->
                if (!rs.next()) null
                else Season(rs.getObject(1) as UUID, rs.getString(2), rs.getString(3), rs.getString(4),
                            rs.getObject(5) as UUID?)
            }
        }

    /**
     * The rules in force. A season that has been pinned (V014's `standings_policy_id`, guarded by V041) is
     * read by its pin, so approving a new tie-break next season cannot re-order a season already played.
     * Otherwise the approved `points` policy governing today: the season's own first, then its league's.
     */
    private fun rules(seasonId: UUID, season: Season, now: Instant): Pair<PointsPolicy, Rules> {
        val on = LocalDate.ofInstant(now, ZoneId.of("Europe/London"))
        val sql = if (season.pinned != null) {
            "SELECT policy_id, version, body::text FROM competition.policy WHERE policy_id = ?"
        } else {
            """SELECT policy_id, version, body::text FROM competition.policy
                WHERE kind = 'points' AND approval_state = 'approved'
                  AND effective_from <= ? AND (effective_to IS NULL OR effective_to >= ?)
                  AND ((authority_kind = 'league_season' AND league_season_id = ?)
                    OR (authority_kind = 'league' AND league_id = ?))
                ORDER BY (authority_kind = 'league_season') DESC, version DESC
                LIMIT 1"""
        }
        val found = connection.prepareStatement(sql).use { ps ->
            if (season.pinned != null) {
                ps.setObject(1, season.pinned)
            } else {
                ps.setObject(1, on); ps.setObject(2, on); ps.setObject(3, seasonId); ps.setObject(4, season.leagueId)
            }
            ps.executeQuery().use { rs ->
                if (!rs.next()) null else Triple(rs.getObject(1) as UUID, rs.getInt(2), rs.getString(3))
            }
        } ?: return PointsPolicy.STANDARD to Rules(
            null, null, mine = false, says = PointsPolicy.STANDARD_SAYS,
            orderedBy = PointsPolicy.STANDARD.chain.map(::stepName),
        )

        val policy = try {
            PointsPolicy.parse(Json.parseObject(found.third))
        } catch (e: IllegalArgumentException) {
            // A league's own rules that THRØ cannot execute are not quietly replaced by THRØ's: the table is
            // refused with the league's own problem in it, because a table ordered by rules the league did
            // not write is worse than no table at all.
            throw Refused("This league's points rules cannot be applied: ${e.message}", 409)
        }
        return policy to Rules(found.first, found.second, mine = true, says = saysOf(policy),
                               orderedBy = policy.chain.map(::stepName))
    }

    private fun divisions(seasonId: UUID, only: UUID?): List<Triple<UUID?, String, Int?>> =
        connection.prepareStatement(
            """SELECT division_id, name, ordinal FROM competition.division
                WHERE league_season_id = ? AND (?::uuid IS NULL OR division_id = ?)
                ORDER BY ordinal""",
        ).use { ps ->
            ps.setObject(1, seasonId); ps.setObject(2, only); ps.setObject(3, only)
            ps.executeQuery().use { rs ->
                generateSequence {
                    if (!rs.next()) null
                    else Triple(rs.getObject(1) as UUID?, rs.getString(2), rs.getInt(3))
                }.toList()
            }
        }

    /** A fixture whose date has gone by with nothing recorded. Said out loud, not left for somebody to notice. */
    private fun awaiting(seasonId: UUID, division: UUID?, now: Instant): Int =
        connection.prepareStatement(
            """SELECT count(*) FROM competition.league_fixture f
                WHERE f.league_season_id = ? AND (?::uuid IS NULL OR f.division_id = ?)
                  AND f.scheduled_at < ?
                  AND NOT EXISTS (SELECT 1 FROM competition.league_fixture_outcome o
                                   WHERE o.fixture_id = f.fixture_id AND o.kind <> 'void'
                                     AND NOT EXISTS (SELECT 1 FROM competition.league_fixture_outcome s
                                                      WHERE s.supersedes_outcome_id = o.outcome_id))""",
        ).use { ps ->
            ps.setObject(1, seasonId); ps.setObject(2, division); ps.setObject(3, division)
            ps.setTimestamp(4, java.sql.Timestamp.from(now))
            ps.executeQuery().use { rs -> if (rs.next()) rs.getInt(1) else 0 }
        }

    private class Tally(val teamId: UUID, val name: String, val won: Int, val drawn: Int, val lost: Int,
                        val legsFor: Int, val legsAgainst: Int, val awardedFor: Int, val awardedAgainst: Int,
                        val evidenced: Int)

    private fun tallies(seasonId: UUID, division: UUID?): List<Tally> =
        connection.prepareStatement(
            """SELECT team_id, team_name, won, drawn, lost, legs_for, legs_against,
                      awarded_for, awarded_against, evidenced
                 FROM competition.league_tallies(?, ?)""",
        ).use { ps ->
            ps.setObject(1, seasonId); ps.setObject(2, division)
            ps.executeQuery().use { rs ->
                generateSequence {
                    if (!rs.next()) null
                    else Tally(rs.getObject(1) as UUID, rs.getString(2), rs.getInt(3), rs.getInt(4), rs.getInt(5),
                               rs.getInt(6), rs.getInt(7), rs.getInt(8), rs.getInt(9), rs.getInt(10))
                }.toList()
            }
        }

    private fun rank(seasonId: UUID, division: UUID?, policy: PointsPolicy): List<Row> {
        val tallies = tallies(seasonId, division)
        if (tallies.isEmpty()) return emptyList()
        val byId = tallies.associateBy { it.teamId.toString() }
        val rows = tallies.map { t ->
            policy.row(t.teamId.toString(), t.won, t.drawn, t.lost, t.legsFor, t.legsAgainst,
                       t.awardedFor, t.awardedAgainst)
        }
        val ranked = Ranker.rank(rows, policy.chain, headToHead(seasonId, division, policy, rows))
        return ranked.map { r ->
            val t = byId.getValue(r.row.competitorId)
            Row(t.teamId, t.name, r.position, r.separatedBy?.let(::stepName),
                r.row.played, r.row.won, r.row.drawn, r.row.lost, r.row.legsFor, r.row.legsAgainst,
                r.row.legDifference, r.row.points, t.awardedFor, t.awardedAgainst, t.evidenced)
        }
    }

    /**
     * Head to head, resolved as a mini-table rather than as a pairwise question.
     *
     * **A pairwise comparator is not an ordering.** Three teams can each have beaten the next — a cycle —
     * and a comparator built on that answers differently depending on the order the rows arrived in, and on
     * a division large enough Java's sort detects the contradiction and throws. So the teams a chain has
     * left level are grouped, the fixtures between the members of a group are scored under the same policy,
     * and the comparison is between two numbers, which cannot cycle.
     */
    private fun headToHead(
        seasonId: UUID, division: UUID?, policy: PointsPolicy, rows: List<StandingsRow>,
    ): (String, String) -> Int {
        if (TieBreak.HEAD_TO_HEAD !in policy.chain) return { _, _ -> 0 }
        val before = policy.chain.takeWhile { it != TieBreak.HEAD_TO_HEAD }
        // Everybody the earlier steps cannot separate belongs to one group, keyed by those steps' values.
        val groups = rows.groupBy { row -> before.map { key(it, row) } }.values.filter { it.size > 1 }
        if (groups.isEmpty()) return { _, _ -> 0 }
        val mini = HashMap<String, Int>()
        for (group in groups) {
            val ids = group.map { it.competitorId }.toSet()
            for ((team, points) in between(seasonId, division, ids, policy)) mini[team] = points
        }
        return { a, b -> (mini[a] ?: 0) - (mini[b] ?: 0) }
    }

    /** What each of [ids] took from the fixtures among themselves, under the league's own rules. */
    private fun between(
        seasonId: UUID, division: UUID?, ids: Set<String>, policy: PointsPolicy,
    ): Map<String, Int> {
        if (ids.size < 2) return emptyMap()
        val uuids = ids.map(UUID::fromString)
        val won = HashMap<String, Int>()
        val drawn = HashMap<String, Int>()
        val lost = HashMap<String, Int>()
        val legs = HashMap<String, Int>()
        connection.prepareStatement(
            """SELECT f.home_team_id, f.away_team_id, o.kind, o.legs_home, o.legs_away, o.to_team_id
                 FROM competition.league_fixture f
                 JOIN competition.league_fixture_outcome o ON o.fixture_id = f.fixture_id
                WHERE f.league_season_id = ? AND (?::uuid IS NULL OR f.division_id = ?)
                  AND o.kind <> 'void'
                  AND NOT EXISTS (SELECT 1 FROM competition.league_fixture_outcome s
                                   WHERE s.supersedes_outcome_id = o.outcome_id)
                  AND f.home_team_id = ANY (?) AND f.away_team_id = ANY (?)""",
        ).use { ps ->
            val array = connection.createArrayOf("uuid", uuids.toTypedArray())
            ps.setObject(1, seasonId); ps.setObject(2, division); ps.setObject(3, division)
            ps.setArray(4, array); ps.setArray(5, array)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    val home = (rs.getObject(1) as UUID).toString()
                    val away = (rs.getObject(2) as UUID).toString()
                    val kind = rs.getString(3)
                    if (kind == "played") {
                        val hl = rs.getInt(4)
                        val al = rs.getInt(5)
                        legs[home] = (legs[home] ?: 0) + hl
                        legs[away] = (legs[away] ?: 0) + al
                        when {
                            hl > al -> { won[home] = (won[home] ?: 0) + 1; lost[away] = (lost[away] ?: 0) + 1 }
                            hl < al -> { won[away] = (won[away] ?: 0) + 1; lost[home] = (lost[home] ?: 0) + 1 }
                            else -> { drawn[home] = (drawn[home] ?: 0) + 1; drawn[away] = (drawn[away] ?: 0) + 1 }
                        }
                    } else {
                        val to = (rs.getObject(6) as UUID?)?.toString()
                        val other = if (to == home) away else home
                        if (to != null) won[to] = (won[to] ?: 0) + 1
                        lost[other] = (lost[other] ?: 0) + 1
                    }
                }
            }
        }
        return ids.associateWith { id ->
            policy.row(id, won[id] ?: 0, drawn[id] ?: 0, lost[id] ?: 0, legs[id] ?: 0, 0).points
        }
    }

    /** The value a chain step orders by, so two rows can be told level under it without sorting them. */
    private fun key(step: TieBreak, row: StandingsRow): Int = when (step) {
        TieBreak.POINTS -> row.points
        TieBreak.LEG_DIFFERENCE -> row.legDifference
        TieBreak.LEGS_FOR -> row.legsFor
        TieBreak.PLAYED -> row.played
        TieBreak.HEAD_TO_HEAD -> 0
    }

    /** The name a league writes in its own policy, so what it reads back is what it wrote. */
    private fun stepName(step: TieBreak): String = step.name.lowercase()

    private fun saysOf(p: PointsPolicy): String {
        val head = "${p.win} ${if (p.win == 1) "point" else "points"} a win, ${p.draw} a draw"
        val leg = if (p.perLegWon > 0) ", and ${p.perLegWon} for every leg won" else ""
        return "$head$leg. This league's own rules."
    }

    public fun json(t: Table): String {
        fun q(s: String?) = s?.let { "\"" + it.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\"" } ?: "null"
        val divisions = t.divisions.joinToString(",") { d ->
            """{"divisionId":${d.divisionId?.let { "\"$it\"" } ?: "null"},"name":${q(d.name)},""" +
                """"ordinal":${d.ordinal ?: "null"},"awaitingResults":${d.awaitingResults},"rows":[""" +
                d.rows.joinToString(",") { r ->
                    """{"position":${r.position},"separatedBy":${q(r.separatedBy)},"teamId":"${r.teamId}",""" +
                        """"name":${q(r.name)},"played":${r.played},"won":${r.won},"drawn":${r.drawn},""" +
                        """"lost":${r.lost},"legsFor":${r.legsFor},"legsAgainst":${r.legsAgainst},""" +
                        """"legDifference":${r.legDifference},"points":${r.points},""" +
                        """"awardedFor":${r.awardedFor},"awardedAgainst":${r.awardedAgainst},""" +
                        """"evidenced":${r.evidenced}}"""
                } + "]}"
        }
        return """{"leagueSeasonId":"${t.leagueSeasonId}","leagueId":"${t.leagueId}","league":${q(t.league)},""" +
            """"label":${q(t.label)},"state":${q(t.state)},""" +
            """"rules":{"policyId":${t.rules.policyId?.let { "\"$it\"" } ?: "null"},""" +
            // "whose" rather than a boolean: `"leagues":true` reads like a list of leagues, and a name that
            // says which of the two it is leaves room for a third answer without changing the shape.
            """"version":${t.rules.version ?: "null"},"whose":${q(if (t.rules.mine) "league" else "thro")},""" +
            """"says":${q(t.rules.says)},""" +
            """"orderedBy":[${t.rules.orderedBy.joinToString(",") { q(it) }}]},""" +
            """"divisions":[$divisions]}"""
    }
}
