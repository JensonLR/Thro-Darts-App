package thro.api

import java.sql.Connection
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * V014 over a populated V013 database: nothing is lost.
 *
 * THRØ has never run, so there is no production data to protect — and the migration is still
 * written and tested as if there were, because the day one exists is not the day to find out the
 * habit was never formed. The world as V013 held it is written first: an event with a free-text
 * venue, entries keyed on bare competitor identifiers, a first-round draw with a bye, a check-in
 * with its grant, and an authorization tuple. Then V014 is applied and every one of them is read
 * back.
 *
 * Skipped cleanly when no database is configured, rather than passing silently.
 */
class MigrationTest {

    @Test
    fun `V014 preserves every row a V013 database held`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — migration test skipped")
            return
        }
        val c: Connection = TestDatabase.migratedUpTo(13)
        var passed = 0
        fun check(name: String, cond: Boolean) {
            assertTrue(cond, "FAILED: $name")
            println("  PASS  $name")
            passed++
        }

        // --- the world as V013 held it -----------------------------------------------------------
        val event = UUID.randomUUID()
        val organiser = UUID.randomUUID()
        val device = UUID.randomUUID()
        val players = List(5) { UUID.randomUUID() }
        c.prepareStatement(
            "INSERT INTO competition.event (event_id, name, venue, starts_at, session_ends_at) VALUES (?, 'Legacy Open', 'The Red Lion', now(), now() + interval '10 hours')",
        ).use { ps -> ps.setObject(1, event); ps.executeUpdate() }
        players.forEachIndexed { i, p ->
            c.prepareStatement("INSERT INTO competition.entry (entry_id, event_id, competitor_id, seed) VALUES (?, ?, ?, ?)")
                .use { ps -> ps.setObject(1, UUID.randomUUID()); ps.setObject(2, event); ps.setObject(3, p); ps.setInt(4, i + 1); ps.executeUpdate() }
        }
        // Five entrants: bracket 8, three byes, one preliminary match.
        val ties = listOf(
            Triple(1, players[0], null), Triple(2, players[1], null), Triple(3, players[2], null),
            Triple(4, players[3], players[4]),
        )
        ties.forEach { (pos, home, away) ->
            c.prepareStatement(
                "INSERT INTO competition.fixture (fixture_id, event_id, round_number, position, home_id, away_id, is_bye) VALUES (?, ?, 1, ?, ?, ?, ?)",
            ).use { ps ->
                ps.setObject(1, UUID.randomUUID()); ps.setObject(2, event); ps.setInt(3, pos)
                ps.setObject(4, home); ps.setObject(5, away); ps.setBoolean(6, away == null); ps.executeUpdate()
            }
        }
        val grant = UUID.randomUUID()
        c.prepareStatement(
            "INSERT INTO trust.scoring_grant (grant_id, event_id, actor_id, device_id, actor_role, expires_at) VALUES (?, ?, ?, ?, 'participant', now() + interval '34 hours')",
        ).use { ps -> ps.setObject(1, grant); ps.setObject(2, event); ps.setObject(3, players[0]); ps.setObject(4, device); ps.executeUpdate() }
        c.prepareStatement(
            "INSERT INTO competition.check_in (event_id, competitor_id, device_id, grant_id) VALUES (?, ?, ?, ?)",
        ).use { ps -> ps.setObject(1, event); ps.setObject(2, players[0]); ps.setObject(3, device); ps.setObject(4, grant); ps.executeUpdate() }
        c.prepareStatement(
            "INSERT INTO authz.relation (subject_id, relation, object_type, object_id) VALUES (?, 'organiser', 'event', ?)",
        ).use { ps -> ps.setObject(1, organiser); ps.setString(2, event.toString()); ps.executeUpdate() }

        // --- V014 ------------------------------------------------------------------------------------
        TestDatabase.apply(c, after = 13)

        // --- and the world afterwards -------------------------------------------------------------
        fun one(sql: String, vararg args: Any): Array<Any?> {
            c.prepareStatement(sql).use { ps ->
                args.forEachIndexed { i, a -> ps.setObject(i + 1, a) }
                ps.executeQuery().use { rs ->
                    rs.next()
                    return Array(rs.metaData.columnCount) { rs.getObject(it + 1) }
                }
            }
        }
        val ev = one("SELECT name, venue_label, entrant_kind, access, state FROM competition.event WHERE event_id = ?", event)
        check("the event survives with its free-text venue as a label", ev[0] == "Legacy Open" && ev[1] == "The Red Lion")
        check("and defaults to what it always was: an open event of single players", ev[2] == "player" && ev[3] == "open")

        val entries = one("SELECT count(*), count(*) FILTER (WHERE entrant_kind = 'player' AND player_id = competitor_id), array_agg(seed ORDER BY seed) FROM competition.entry WHERE event_id = ?", event)
        check("every entry survives", (entries[0] as Number).toInt() == 5)
        check("each is typed as a player whose competitor id is unchanged", (entries[1] as Number).toInt() == 5)
        check("seeds are intact", (entries[2] as java.sql.Array).array.let { (it as Array<*>).map { s -> (s as Number).toInt() } } == listOf(1, 2, 3, 4, 5))

        val legacy = one("SELECT count(*) FROM competition.player WHERE player_id = ANY(?) AND source = 'legacy'", c.createArrayOf("uuid", players.toTypedArray()))
        check("a legacy player record exists for each bare identifier, holding no personal data", (legacy[0] as Number).toInt() == 5)

        val tiesAfter = one("SELECT count(*), count(*) FILTER (WHERE is_bye), count(*) FILTER (WHERE NOT is_bye) FROM competition.bracket_tie WHERE event_id = ?", event)
        check("the draw survives under its new name, byes and all", (tiesAfter[0] as Number).toInt() == 4 && (tiesAfter[1] as Number).toInt() == 3 && (tiesAfter[2] as Number).toInt() == 1)
        val tieCols = one("SELECT count(*) FROM information_schema.tables WHERE table_schema = 'competition' AND table_name = 'fixture'")
        check("no table named competition.fixture remains to be written against by old SQL", (tieCols[0] as Number).toInt() == 0)
        val byeGuard = try {
            c.prepareStatement("UPDATE competition.bracket_tie SET match_id = ? WHERE event_id = ? AND is_bye").use { ps ->
                val m = UUID.randomUUID()
                Matches(c).open(m, UUID.randomUUID(), UUID.randomUUID(), "H", "A", playtestFormat(thro.engine.PlayerId("H")))
                ps.setObject(1, m); ps.setObject(2, event); ps.executeUpdate()
            }
            false
        } catch (e: org.postgresql.util.PSQLException) {
            e.message!!.contains("bye_is_never_a_match")
        }
        check("the renamed table keeps its constraints", byeGuard)

        val ci = one("SELECT competitor_id, player_id, grant_id FROM competition.check_in WHERE event_id = ?", event)
        check("the check-in survives with its grant", ci[0] == players[0] && ci[2] == grant)
        check("and its player is backfilled from the competitor", ci[1] == players[0])

        val rel = one("SELECT count(*) FILTER (WHERE revoked_at IS NULL), count(*) FROM authz.relation WHERE subject_id = ?", organiser)
        check("the authorization tuple survives, live", (rel[0] as Number).toInt() == 1 && (rel[1] as Number).toInt() == 1)

        val gr = one("SELECT count(*) FROM trust.scoring_grant WHERE grant_id = ?", grant)
        check("the grant is untouched", (gr[0] as Number).toInt() == 1)

        // The migration is a deploy step run by the owner; the application roles gained nothing
        // they should not have.
        val del = one(
            """
            SELECT count(*) FROM information_schema.role_table_grants
             WHERE table_schema IN ('competition') AND privilege_type IN ('DELETE','TRUNCATE')
               AND grantee LIKE 'app\_%'
            """.trimIndent(),
        )
        check("no application role holds DELETE or TRUNCATE on any competition table", (del[0] as Number).toInt() == 0)

        println("  $passed migration properties held")
        assertEquals(14, passed)
    }
}
