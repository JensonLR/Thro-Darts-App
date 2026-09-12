package thro.api

import java.sql.Connection
import java.time.Instant
import java.util.UUID

/**
 * A league season's fixtures, publicly (PD-056).
 *
 * The other half of giving a league its own data back: a table says how the season stands, and this says
 * what is still to play and what has already been decided. Both are read from the same rows, so neither can
 * disagree with the other.
 *
 * **Public means public**, as it does for the leagues themselves: a team or venue marked private is not
 * named here. The fixture is still listed, because it happened and hiding it would leave a hole in a league's
 * own calendar — the private side is simply unnamed, which is the same answer the app gives for a player who
 * may not be disclosed.
 */
public class Fixtures(private val connection: Connection) {

    /** What a fixture finished as, where it has. Null while nobody has decided anything. */
    public data class Decided(val kind: String, val legsHome: Int?, val legsAway: Int?, val awardedToHome: Boolean?)

    public data class Fixture(
        val fixtureId: UUID,
        val divisionId: UUID?, val division: String?,
        val scheduledAt: Instant,
        /** scheduled, rearranged or postponed — a fixture's own lifecycle, not its result. */
        val state: String,
        val home: String?, val away: String?,
        val venue: String?, val locality: String?,
        val decided: Decided?,
    )

    /** True when THRØ has this season at all, so a route can tell "no fixtures" from "no season". */
    public fun seasonExists(leagueSeasonId: UUID): Boolean =
        connection.prepareStatement("SELECT 1 FROM competition.league_season WHERE league_season_id = ?").use { ps ->
            ps.setObject(1, leagueSeasonId)
            ps.executeQuery().use { it.next() }
        }

    public fun of(leagueSeasonId: UUID): List<Fixture> =
        connection.prepareStatement(
            """
            SELECT f.fixture_id, f.division_id, d.name, f.scheduled_at, f.schedule_state,
                   h.name, a.name, v.name, v.locality,
                   o.kind, o.legs_home, o.legs_away, (o.to_team_id = f.home_team_id)
              FROM competition.league_fixture f
              -- A private team is unnamed rather than absent: the join is left, so the fixture survives it.
              LEFT JOIN competition.team h ON h.team_id = f.home_team_id AND h.visibility = 'public'
              LEFT JOIN competition.team a ON a.team_id = f.away_team_id AND a.visibility = 'public'
              LEFT JOIN competition.division d ON d.division_id = f.division_id
              LEFT JOIN competition.venue v ON v.venue_id = f.venue_id AND v.visibility = 'public'
              -- The live outcome, exactly as the tallies define it (V041, V042): unsuperseded, voids out.
              LEFT JOIN competition.league_fixture_outcome o
                     ON o.fixture_id = f.fixture_id AND o.kind <> 'void'
                    AND NOT EXISTS (SELECT 1 FROM competition.league_fixture_outcome s
                                     WHERE s.supersedes_outcome_id = o.outcome_id)
             WHERE f.league_season_id = ?
             ORDER BY f.scheduled_at, h.name NULLS LAST, f.fixture_id
            """.trimIndent(),
        ).use { ps ->
            ps.setObject(1, leagueSeasonId)
            ps.executeQuery().use { rs ->
                generateSequence {
                    if (!rs.next()) null
                    else {
                        val kind = rs.getString(10)
                        Fixture(
                            fixtureId = rs.getObject(1) as UUID,
                            divisionId = rs.getObject(2) as UUID?, division = rs.getString(3),
                            scheduledAt = rs.getTimestamp(4).toInstant(), state = rs.getString(5),
                            home = rs.getString(6), away = rs.getString(7),
                            venue = rs.getString(8), locality = rs.getString(9),
                            decided = kind?.let {
                                val lh = rs.getInt(11).takeUnless { _ -> rs.wasNull() }
                                val la = rs.getInt(12).takeUnless { _ -> rs.wasNull() }
                                val toHome = rs.getBoolean(13).takeUnless { _ -> rs.wasNull() }
                                Decided(it, lh, la, toHome)
                            },
                        )
                    }
                }.toList()
            }
        }

    public fun json(fixtures: List<Fixture>): String {
        fun q(s: String?) = s?.let { "\"" + it.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\"" } ?: "null"
        return "{\"fixtures\":[" + fixtures.joinToString(",") { f ->
            val decided = f.decided?.let { d ->
                """{"kind":${q(d.kind)},"legsHome":${d.legsHome ?: "null"},"legsAway":${d.legsAway ?: "null"},""" +
                    """"awardedToHome":${d.awardedToHome?.toString() ?: "null"}}"""
            } ?: "null"
            """{"fixtureId":"${f.fixtureId}","divisionId":${f.divisionId?.let { "\"$it\"" } ?: "null"},""" +
                """"division":${q(f.division)},"scheduledAt":"${f.scheduledAt}","state":${q(f.state)},""" +
                """"home":${q(f.home)},"away":${q(f.away)},"venue":${q(f.venue)},"locality":${q(f.locality)},""" +
                """"decided":$decided}"""
        } + "]}"
    }
}
