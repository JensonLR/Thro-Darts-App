package thro.api

import java.io.File
import java.sql.Connection
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * The league import (PD-033) against a real database: what it writes, what it refuses to write
 * twice, what it never touches, and that nothing it writes is a person.
 */
class SeedTest {

    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()

    private val seedFile: File by lazy {
        generateSequence(File(".").absoluteFile) { it.parentFile }
            .map { File(it, "services/api/seed/leagues/teesside.json") }.first { it.parentFile.parentFile.isDirectory }
    }

    private fun count(c: Connection, sql: String): Int =
        c.createStatement().use { st -> st.executeQuery(sql).use { rs -> rs.next(); rs.getInt(1) } }

    @Test
    fun `the Teesside seed imports once, and a second run changes nothing`() {
        if (!configured) return
        migrated().use { c ->
            val first = Seed(c, Instant.parse("2026-09-10T12:00:00Z")).importFile(seedFile)
            assertEquals(3, first.leagues, "three leagues: Stockton Thursday, Stockton Monday Mixed, Redcar")
            assertEquals(5, first.seasons)
            assertEquals(6, first.divisions)
            assertEquals(18, first.venues)
            assertTrue(first.teams in 40..60, "distinct organisations, not team-seasons (77): ${first.teams}")
            assertEquals(77, first.affiliations, "every team-season is an affiliation")
            assertTrue(first.sourceRecords > 100)

            val again = Seed(c, Instant.parse("2026-09-10T13:00:00Z")).importFile(seedFile)
            assertEquals(Seed.Outcome(0, 0, 0, 0, 0, 0, 0, 0), again, "idempotent by natural key")

            // The same organisation in two leagues is one team with two affiliations.
            assertEquals(1, count(c, "SELECT count(*) FROM competition.team WHERE name = 'Thornaby F.C'"))
            assertEquals(4, count(c, """SELECT count(*) FROM competition.team_affiliation ta JOIN competition.team t ON t.team_id = ta.team_id
                                          WHERE t.name = 'Thornaby F.C'"""), "three Thursday seasons and one Monday")
            // Sheraton A on a Thursday and Sheraton A on a Monday are the same pub's organisation.
            assertEquals(1, count(c, "SELECT count(*) FROM competition.team WHERE name = 'Sheraton A'"))

            // Nothing is a person.
            assertEquals(0, count(c, "SELECT count(*) FROM competition.player"))
            assertEquals(0, count(c, "SELECT count(*) FROM competition.team_membership"))
            assertEquals(0, count(c, "SELECT count(*) FROM competition.player_registration"))

            // Every imported row says where it came from.
            for (kind in listOf("league", "league_season", "division", "team", "venue", "team_affiliation")) {
                val table = if (kind == "league_season") "league_season" else kind
                val key = when (kind) { "league_season" -> "league_season_id"; "team_affiliation" -> "affiliation_id"; else -> "${kind}_id" }
                assertEquals(0, count(c, """SELECT count(*) FROM competition.$table x
                    WHERE NOT EXISTS (SELECT 1 FROM competition.source_record sr WHERE sr.subject_kind = '$kind' AND sr.subject_id = x.$key)"""),
                    "every $kind carries a source record")
            }
            // A venue's connection to its team is an inference and is recorded as one.
            val basis = c.createStatement().use { st ->
                st.executeQuery("""SELECT sr.basis FROM competition.source_record sr
                    JOIN competition.team_venue_tenure tv ON tv.tenure_id = sr.subject_id AND sr.subject_kind = 'team_venue_tenure'
                    JOIN competition.team t ON t.team_id = tv.team_id WHERE t.name = 'Blue Bell'""").use { rs -> rs.next(); rs.getString(1) }
            }
            assertTrue(basis.startsWith("inferred from the team's name"), basis)
            // The season's span says it is approximate.
            assertTrue(count(c, "SELECT count(*) FROM competition.source_record WHERE subject_kind = 'league_season' AND basis LIKE 'approximate:%'") == 5)
            // The map has coordinates to plot.
            assertEquals(18, count(c, "SELECT count(*) FROM competition.venue WHERE latitude IS NOT NULL AND postcode IS NOT NULL OR (latitude IS NOT NULL AND name = 'Marske Cricket Club')"))
        }
    }

    @Test
    fun `the directory places hundreds of leagues, and one already imported from its own pages is not made twice`() {
        if (!configured) return
        migrated().use { c ->
            Seed(c, Instant.parse("2026-09-11T08:00:00Z")).importFile(seedFile)
            val directory = File(seedFile.parentFile, "directory.json")
            val listed = (Json.parseObject(directory.readText())["leagues"] as List<*>).size
            assertTrue(listed >= 300, "the directory places $listed leagues")

            val first = Seed(c, Instant.parse("2026-09-11T09:00:00Z")).importFile(directory)
            assertEquals(listed - 3, first.leagues, "Stockton Thursday, Stockton Monday and Redcar are already here: $first")
            assertEquals(0, first.seasons); assertEquals(0, first.divisions); assertEquals(0, first.teams); assertEquals(0, first.venues)
            // Stockton Thursday is listed under a shorter name than its own pages use; the address is the
            // same league, so it gets its point and not a twin.
            assertEquals(1, count(c, "SELECT count(*) FROM competition.league WHERE name ILIKE '%Stockton%Thursday%'"))
            assertEquals(listed, count(c, "SELECT count(*) FROM competition.league"))
            assertEquals(listed, count(c, "SELECT count(*) FROM competition.league WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND website IS NOT NULL"))
            // Idempotent, like the other file.
            assertEquals(Seed.Outcome(0, 0, 0, 0, 0, 0, 0, 0), Seed(c, Instant.parse("2026-09-11T10:00:00Z")).importFile(directory))
            // The public front lists every league, placed, with or without a season — and still no person.
            val all = Leagues(c).all()
            assertEquals(listed, all.size)
            assertTrue(all.all { it.latitude != null && it.longitude != null && it.website != null })
            assertEquals(3, all.count { it.seasons.isNotEmpty() }, "seasons only where pages were read")
            val json = Leagues(c).json(all)
            assertTrue(json.contains(""""latitude":57.50"""), "Peterhead is on the wire")
            assertTrue(!json.contains("player"))
            assertEquals(0, count(c, "SELECT count(*) FROM competition.player"))
            // Every league says where it was read from.
            assertEquals(0, count(c, """SELECT count(*) FROM competition.league x
                WHERE NOT EXISTS (SELECT 1 FROM competition.source_record sr WHERE sr.subject_kind = 'league' AND sr.subject_id = x.league_id)"""))
        }
    }

    /**
     * Two leagues, no locality on either — which is every league the directory places (PD-037) — and a pub
     * name they share. They are two teams. The fallback that matches a team already recorded by hand used
     * `locality IS NOT DISTINCT FROM`, so NULL matched NULL and the Red Lion in Halifax would have become
     * the Red Lion in Burnley the moment a second league was imported.
     */
    @Test
    fun `a pub name two leagues share is two teams when neither says where it is`() {
        if (!configured) return
        migrated().use { c ->
            fun league(key: String, name: String, host: String) = """
                {"key":"$key","name":"$name","short_name":null,"locality":null,"night":null,
                 "platform":"LeagueRepublic","url":"https://$host/","notes":"",
                 "seasons":[{"label":"2025-2026","starts_on":"2025-09-01","ends_on":"2026-05-31",
                   "span_basis":"approximate: read from the season label",
                   "divisions":[{"name":"Division One","ordinal":1,"source_url":"https://$host/fg/1_1.html",
                     "teams":["The Red Lion"]}]}]}
            """.trimIndent()
            val json = """
                {"retrieved_on":"2026-09-11","method":"test","personal_data":"none","venues":[],"team_venues":[],
                 "leagues":[${league("halifax", "Halifax & District Darts League", "halifaxdartsleague.example")},
                            ${league("burnley", "Burnley & District Darts League", "burnleydartsleague.example")}]}
            """.trimIndent()
            val file = File.createTempFile("thro-two-leagues", ".json").also { it.writeText(json); it.deleteOnExit() }

            val made = Seed(c, Instant.parse("2026-09-11T12:00:00Z")).importFile(file)
            assertEquals(2, made.leagues)
            assertEquals(2, made.teams, "the Red Lion in Halifax is not the Red Lion in Burnley")
            assertEquals(2, count(c, "SELECT count(*) FROM competition.team WHERE name = 'The Red Lion'"))
            assertEquals(0, Seed(c, Instant.parse("2026-09-11T12:00:00Z")).importFile(file).teams,
                         "and importing the same file again makes neither of them again")
        }
    }

    @Test
    fun `what a secretary has recorded is not overwritten by an import`() {
        if (!configured) return
        migrated().use { c ->
            val org = Organisations(c)
            // A secretary already has the Sun Inn's team at a different venue, and the venue at other coordinates.
            val team = org.createTeam("Sun Inn", "Stockton-on-Tees")
            val theirs = org.createVenue("The Sun Inn (function room)", "Stockton-on-Tees")
            org.openTenure(team, theirs, from = Instant.parse("2025-08-01T00:00:00Z"))
            Seed(c, Instant.parse("2026-09-10T12:00:00Z")).importFile(seedFile)
            // Their tenure stands; the import did not open a second home.
            assertEquals(1, count(c, "SELECT count(*) FROM competition.team_venue_tenure WHERE team_id = '$team' AND kind = 'home' AND valid_until IS NULL"))
            assertEquals(theirs, c.createStatement().use { st -> st.executeQuery("SELECT venue_id FROM competition.team_venue_tenure WHERE team_id = '$team' AND valid_until IS NULL").use { rs -> rs.next(); rs.getObject(1) as UUID } })
            // But a second 'Sun Inn' team was not invented either: the import affiliated theirs.
            assertEquals(1, count(c, "SELECT count(*) FROM competition.team WHERE name = 'Sun Inn'"))
            assertEquals(3, count(c, "SELECT count(*) FROM competition.team_affiliation WHERE team_id = '$team'"))
        }
    }

    @Test
    fun `the public front reads back what was imported, and nothing private`() {
        if (!configured) return
        migrated().use { c ->
            Seed(c, Instant.parse("2026-09-10T12:00:00Z")).importFile(seedFile)
            val all = Leagues(c).all(now = Instant.parse("2026-01-15T12:00:00Z"))
            assertEquals(3, all.size)
            val thursday = all.first { it.playsOn == "Thursday" }
            assertEquals("Stockton and District Thursday Night Darts League", thursday.name)
            assertEquals(listOf("2025-2026", "2024-2025", "2023-2024"), thursday.seasons.map { it.label }, "newest first")
            assertTrue(thursday.seasons[0].current && !thursday.seasons[1].current)
            assertEquals(18, thursday.seasons[0].divisions[0].teams.size)
            val blueBell = thursday.seasons[0].divisions[0].teams.first { it.name == "Blue Bell" }
            assertNotNull(blueBell.venue); assertEquals("TS16 0JF", blueBell.venue!!.postcode)
            assertTrue(blueBell.venue!!.basis!!.startsWith("inferred"))
            assertEquals("LeagueRepublic", thursday.sources.single().source)

            assertEquals(1, Leagues(c).all(locality = "redcar").size)
            assertEquals(0, Leagues(c).all(locality = "Carlisle").size)

            // A private team is not on the front.
            c.createStatement().use { st -> st.execute("UPDATE competition.team SET visibility = 'private', row_version = row_version + 1 WHERE name = 'Blue Bell'") }
            assertTrue(Leagues(c).all().first { it.playsOn == "Thursday" }.seasons[0].divisions[0].teams.none { it.name == "Blue Bell" })

            val json = Leagues(c).json(all)
            assertTrue(json.startsWith("""{"leagues":[{"leagueId":""""))
            assertTrue(json.contains(""""postcode":"TS16 0JF""""))
            assertTrue(!json.contains("player"), "no person, not even the word")
        }
    }
}
