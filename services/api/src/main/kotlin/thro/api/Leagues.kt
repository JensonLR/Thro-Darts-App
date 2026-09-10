package thro.api

import java.sql.Connection
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

/**
 * The public front of the leagues: league → season → division → team → home venue, with where
 * each came from. What the Discover tab draws and what the map plots (PD-033).
 *
 * Public means public: only `visibility = 'public'` teams and venues appear, and nothing on any
 * row is a person — a team's front is its name, its venue and its competition (PD-009). The
 * provenance travels with it: each league lists its sources, and a venue that was *inferred* from
 * a team's name says so on the row, because the difference between "the secretary said" and "a
 * pub called The Blue Bell probably hosts the team called Blue Bell" is a difference a player
 * should be able to see.
 */
public class Leagues(private val connection: Connection) {

    public data class Venue(val venueId: UUID, val name: String, val locality: String?, val postcode: String?,
                            val latitude: Double?, val longitude: Double?, val basis: String?)
    public data class Team(val teamId: UUID, val name: String, val venue: Venue?)
    public data class Division(val divisionId: UUID, val name: String, val ordinal: Int, val teams: List<Team>)
    public data class Season(val leagueSeasonId: UUID, val label: String, val startsOn: LocalDate, val endsOn: LocalDate,
                             val current: Boolean, val divisions: List<Division>)
    public data class Source(val source: String, val url: String?, val retrievedOn: LocalDate)
    public data class League(val leagueId: UUID, val name: String, val shortName: String?, val playsOn: String?,
                             val locality: String?, val sources: List<Source>, val seasons: List<Season>)

    private val london = ZoneId.of("Europe/London")

    /** Every league, or those whose locality matches [locality] (case-insensitively, as a substring). */
    public fun all(locality: String? = null, now: Instant = Instant.now()): List<League> {
        val today = now.atZone(london).toLocalDate()
        val leagues = linkedMapOf<UUID, League>()
        val seasons = linkedMapOf<UUID, MutableList<Season>>()
        val divisions = linkedMapOf<UUID, MutableList<Division>>()
        val teams = linkedMapOf<UUID, MutableList<Team>>()
        connection.prepareStatement(
            """
            SELECT l.league_id, l.name, l.short_name, l.plays_on, l.locality,
                   ls.league_season_id, ls.label, ls.starts_on, ls.ends_on,
                   d.division_id, d.name, d.ordinal,
                   t.team_id, t.name,
                   v.venue_id, v.name, v.locality, v.postcode, v.latitude, v.longitude,
                   (SELECT sr.basis FROM competition.source_record sr
                     WHERE sr.subject_kind = 'team_venue_tenure' AND sr.subject_id = tv.tenure_id
                     ORDER BY sr.retrieved_on DESC, sr.recorded_at DESC LIMIT 1)
              FROM competition.league l
              JOIN competition.league_season ls ON ls.league_id = l.league_id
              LEFT JOIN competition.division d ON d.league_season_id = ls.league_season_id
              LEFT JOIN competition.team_affiliation ta
                     ON ta.league_season_id = ls.league_season_id AND ta.valid_until IS NULL
                    AND ta.division_id IS NOT DISTINCT FROM d.division_id
              LEFT JOIN competition.team t ON t.team_id = ta.team_id AND t.visibility = 'public' AND t.dissolved_at IS NULL
              LEFT JOIN competition.team_venue_tenure tv ON tv.team_id = t.team_id AND tv.kind = 'home' AND tv.valid_until IS NULL
              LEFT JOIN competition.venue v ON v.venue_id = tv.venue_id AND v.visibility = 'public'
             WHERE ? IS NULL OR l.locality ILIKE '%' || ? || '%'
             ORDER BY l.name, ls.starts_on DESC, ls.label, d.ordinal NULLS LAST, t.name
            """.trimIndent(),
        ).use { ps ->
            ps.setString(1, locality); ps.setString(2, locality)
            ps.executeQuery().use { rs ->
                while (rs.next()) {
                    val leagueId = rs.getObject(1) as UUID
                    leagues.getOrPut(leagueId) {
                        League(leagueId, rs.getString(2), rs.getString(3), rs.getString(4), rs.getString(5), sourcesOf(leagueId), emptyList())
                    }
                    val seasonId = rs.getObject(6) as UUID
                    val seasonList = seasons.getOrPut(leagueId) { mutableListOf() }
                    if (seasonList.none { it.leagueSeasonId == seasonId }) {
                        val starts = rs.getObject(8, LocalDate::class.java); val ends = rs.getObject(9, LocalDate::class.java)
                        seasonList += Season(seasonId, rs.getString(7), starts, ends, !today.isBefore(starts) && !today.isAfter(ends), emptyList())
                    }
                    val divisionId = rs.getObject(10) as UUID? ?: continue
                    val divisionList = divisions.getOrPut(seasonId) { mutableListOf() }
                    if (divisionList.none { it.divisionId == divisionId }) divisionList += Division(divisionId, rs.getString(11), rs.getInt(12), emptyList())
                    val teamId = rs.getObject(13) as UUID? ?: continue
                    val venue = (rs.getObject(15) as UUID?)?.let { vid ->
                        Venue(vid, rs.getString(16), rs.getString(17), rs.getString(18),
                              rs.getBigDecimal(19)?.toDouble(), rs.getBigDecimal(20)?.toDouble(), rs.getString(21))
                    }
                    teams.getOrPut(divisionId) { mutableListOf() } += Team(teamId, rs.getString(14), venue)
                }
            }
        }
        return leagues.values.map { l ->
            l.copy(seasons = seasons[l.leagueId].orEmpty().map { s ->
                s.copy(divisions = divisions[s.leagueSeasonId].orEmpty().map { d -> d.copy(teams = teams[d.divisionId].orEmpty()) })
            })
        }
    }

    private fun sourcesOf(leagueId: UUID): List<Source> =
        connection.prepareStatement(
            """SELECT source, source_url, max(retrieved_on) FROM competition.source_record
                WHERE subject_kind = 'league' AND subject_id = ? GROUP BY source, source_url ORDER BY source""",
        ).use { ps ->
            ps.setObject(1, leagueId)
            ps.executeQuery().use { rs ->
                generateSequence { if (rs.next()) Source(rs.getString(1), rs.getString(2), rs.getObject(3, LocalDate::class.java)) else null }.toList()
            }
        }

    /** The JSON the route answers with. Hand-rendered like every other answer in this service. */
    public fun json(leagues: List<League>): String {
        fun q(s: String?) = s?.let { "\"" + it.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\"" } ?: "null"
        return "{\"leagues\":[" + leagues.joinToString(",") { l ->
            """{"leagueId":"${l.leagueId}","name":${q(l.name)},"shortName":${q(l.shortName)},"playsOn":${q(l.playsOn)},"locality":${q(l.locality)},""" +
                """"sources":[${l.sources.joinToString(",") { """{"source":${q(it.source)},"url":${q(it.url)},"retrievedOn":"${it.retrievedOn}"}""" }}],""" +
                """"seasons":[${l.seasons.joinToString(",") { s ->
                    """{"leagueSeasonId":"${s.leagueSeasonId}","label":${q(s.label)},"startsOn":"${s.startsOn}","endsOn":"${s.endsOn}","current":${s.current},""" +
                        """"divisions":[${s.divisions.joinToString(",") { d ->
                            """{"divisionId":"${d.divisionId}","name":${q(d.name)},"ordinal":${d.ordinal},"teams":[${d.teams.joinToString(",") { t ->
                                """{"teamId":"${t.teamId}","name":${q(t.name)},"venue":""" + (t.venue?.let { v ->
                                    """{"venueId":"${v.venueId}","name":${q(v.name)},"locality":${q(v.locality)},"postcode":${q(v.postcode)},"latitude":${v.latitude ?: "null"},"longitude":${v.longitude ?: "null"},"basis":${q(v.basis)}}"""
                                } ?: "null") + "}"
                            }}]}"""
                        }}]}"""
                }}]}"""
        } + "]}"
    }
}
