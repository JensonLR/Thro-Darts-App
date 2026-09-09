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
        // A match as V006 stored it: two names on the aggregate, and every visit payload naming its
        // thrower by that name. The one thing V018 rewrites.
        val named = UUID.randomUUID()
        c.prepareStatement(
            """
            INSERT INTO evidence.match (match_id, home_id, away_id, home_name, away_name, starting_score, in_rule, out_rule, legs_mode, legs_target, throw_first)
            VALUES (?, ?, ?, 'Sam Wilson', 'Jo Bloggs', 501, 'straight', 'double', 'first_to', 5, ?)
            """.trimIndent(),
        ).use { ps -> ps.setObject(1, named); ps.setObject(2, players[0]); ps.setObject(3, players[1]); ps.setObject(4, players[0]); ps.executeUpdate() }
        fun visit(match: UUID, seq: Int, type: String, who: String) {
            c.prepareStatement(
                """
                INSERT INTO evidence.event (event_id, match_id, device_id, device_seq, event_type, schema_version, correlation_id, actor_id, actor_role, occurred_at, occurred_tz, payload)
                VALUES (?, ?, ?, ?, ?, 1, ?, ?, 'participant', now(), 'Europe/London', ?::jsonb)
                """.trimIndent(),
            ).use { ps ->
                ps.setObject(1, UUID.randomUUID()); ps.setObject(2, match); ps.setObject(3, device); ps.setLong(4, seq.toLong())
                ps.setString(5, type); ps.setObject(6, UUID.randomUUID()); ps.setObject(7, players[0])
                ps.setString(8, """{"player":"$who","visitTotal":60,"remainingAfter":441}"""); ps.executeUpdate()
            }
        }
        visit(named, 1, "VisitRecorded", "Sam Wilson"); visit(named, 2, "VisitRecorded", "Jo Bloggs")
        visit(named, 3, "VisitRecorded", "Sam Wilson"); visit(named, 4, "VisitCorrected", "Jo Bloggs")
        // A second match in which a Sam Wilson — the same string, whoever it is — sits AWAY. The
        // rewrite must read each match's own names, or this visit would land on the wrong seat.
        val shared = UUID.randomUUID()
        c.prepareStatement(
            """
            INSERT INTO evidence.match (match_id, home_id, away_id, home_name, away_name, starting_score, in_rule, out_rule, legs_mode, legs_target, throw_first)
            VALUES (?, ?, ?, 'Alex Brown', 'Sam Wilson', 501, 'straight', 'double', 'first_to', 5, ?)
            """.trimIndent(),
        ).use { ps -> ps.setObject(1, shared); ps.setObject(2, players[2]); ps.setObject(3, players[3]); ps.setObject(4, players[2]); ps.executeUpdate() }
        visit(shared, 1, "VisitRecorded", "Sam Wilson")

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
                Matches(c).open(m, UUID.randomUUID(), UUID.randomUUID(), playtestFormat())
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
        val key = one("SELECT string_agg(a.attname, ',' ORDER BY k.n) FROM pg_constraint c JOIN LATERAL unnest(c.conkey) WITH ORDINALITY k(attnum, n) ON true JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum WHERE c.conrelid = 'competition.check_in'::regclass AND c.contype = 'p'")
        check("a check-in is keyed on the person present, not the entry (V020)", key[0] == "event_id,player_id,device_id")
        val fk = one("SELECT convalidated FROM pg_constraint WHERE conname = 'check_in_is_for_an_entry'")
        check("every legacy check-in named an entry, so the entry rule was validated over them", fk[0] == true)

        val rel = one("SELECT count(*) FILTER (WHERE revoked_at IS NULL), count(*) FROM authz.relation WHERE subject_id = ?", organiser)
        check("the authorization tuple survives, live", (rel[0] as Number).toInt() == 1 && (rel[1] as Number).toInt() == 1)

        val gr = one("SELECT count(*) FROM trust.scoring_grant WHERE grant_id = ?", grant)
        check("the grant is untouched", (gr[0] as Number).toInt() == 1)

        // V018: the names are gone from the aggregate and every payload names a seat instead — the
        // same three visits, in the same order, nothing else in the payload touched.
        val cols = one("SELECT count(*) FROM information_schema.columns WHERE table_schema = 'evidence' AND table_name = 'match' AND column_name IN ('home_name','away_name')")
        check("the aggregate no longer has name columns", (cols[0] as Number).toInt() == 0)
        val seats = one("SELECT array_agg(payload->>'player' ORDER BY device_seq), array_agg((payload->>'remainingAfter')::int ORDER BY device_seq), count(*) FROM evidence.event WHERE match_id = ?", named)
        check("every visit payload — recorded or corrected — now names its seat, in order, with the rest of the payload intact",
            (seats[0] as java.sql.Array).array.let { (it as Array<*>).toList() } == listOf("home", "away", "home", "away") &&
                (seats[1] as java.sql.Array).array.let { (it as Array<*>).map { v -> (v as Number).toInt() } } == listOf(441, 441, 441, 441) &&
                (seats[2] as Number).toInt() == 4)
        val other = one("SELECT payload->>'player' FROM evidence.event WHERE match_id = ?", shared)
        check("a name shared across matches maps by each match's own seats: Sam Wilson is away here", other[0] == "away")
        val noNames = one("SELECT count(*) FROM evidence.event WHERE payload::text LIKE '%Sam Wilson%' OR payload::text LIKE '%Jo Bloggs%' OR payload::text LIKE '%Alex Brown%'")
        check("no display name survives anywhere in the evidence log", (noNames[0] as Number).toInt() == 0)
        val nameRefused = try {
            visit(named, 9, "VisitRecorded", "Sam Wilson"); false
        } catch (e: org.postgresql.util.PSQLException) { e.message!!.contains("visit_names_a_seat") }
        check("and from now on the database refuses a visit whose player is not a seat", nameRefused)
        val aggregate = Matches(c).load(named)
        check("the aggregate still binds the seats to the same two competitors and the same thrower",
            aggregate != null && aggregate.homeId == players[0] && aggregate.awayId == players[1] && aggregate.format.throwFirst == Seat.home)

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
        assertEquals(22, passed)
    }

    /**
     * V018 is a pseudonymisation, and a pseudonymisation that leaves one name behind is not one.
     * A payload naming neither of its match's two names, or a match whose two names are the same,
     * is resolved by a person; the migration refuses rather than guesses, and leaves the database
     * as it found it.
     */
    @Test
    fun `V018 refuses to guess, and leaves the database untouched when it does`() {
        if (!TestDatabase.configured) {
            println("no database configured (set PGHOST) — migration test skipped")
            return
        }
        fun v13WithMatch(home: String, away: String, visitBy: String): Connection {
            val c = TestDatabase.migratedUpTo(13)
            val match = UUID.randomUUID(); val a = UUID.randomUUID(); val b = UUID.randomUUID()
            c.prepareStatement(
                """
                INSERT INTO evidence.match (match_id, home_id, away_id, home_name, away_name, starting_score, in_rule, out_rule, legs_mode, legs_target, throw_first)
                VALUES (?, ?, ?, ?, ?, 501, 'straight', 'double', 'first_to', 5, ?)
                """.trimIndent(),
            ).use { ps -> ps.setObject(1, match); ps.setObject(2, a); ps.setObject(3, b); ps.setString(4, home); ps.setString(5, away); ps.setObject(6, a); ps.executeUpdate() }
            c.prepareStatement(
                """
                INSERT INTO evidence.event (event_id, match_id, device_id, device_seq, event_type, schema_version, correlation_id, actor_id, actor_role, occurred_at, occurred_tz, payload)
                VALUES (?, ?, ?, 1, 'VisitRecorded', 1, ?, ?, 'participant', now(), 'Europe/London', ?::jsonb)
                """.trimIndent(),
            ).use { ps ->
                ps.setObject(1, UUID.randomUUID()); ps.setObject(2, match); ps.setObject(3, UUID.randomUUID()); ps.setObject(4, UUID.randomUUID()); ps.setObject(5, a)
                ps.setString(6, """{"player":"$visitBy","visitTotal":60}"""); ps.executeUpdate()
            }
            return c
        }
        fun refusal(c: Connection): String = try {
            TestDatabase.apply(c, after = 13); "applied"
        } catch (e: IllegalStateException) { e.message!! }
        fun stillNamed(c: Connection): Boolean = c.createStatement().use { st ->
            st.executeQuery("SELECT count(*) FROM information_schema.columns WHERE table_schema = 'evidence' AND table_name = 'match' AND column_name = 'home_name'")
                .use { rs -> rs.next(); rs.getInt(1) == 1 }
        }

        val variant = v13WithMatch("Sam Wilson", "Jo Bloggs", visitBy = "S. Wilson")
        val r1 = refusal(variant)
        assertTrue(r1.contains("neither seat"), "a spelling variant must be refused, got: $r1")
        assertTrue(stillNamed(variant), "a refused V018 must leave the name columns in place")
        println("  PASS  a payload naming neither seat is refused, and the database is left as it was")

        val twins = v13WithMatch("Sam", "Sam", visitBy = "Sam")
        val r2 = refusal(twins)
        assertTrue(r2.contains("identical names"), "identical names with visits must be refused, got: $r2")
        assertTrue(stillNamed(twins))
        println("  PASS  a match whose two seats share a name is refused rather than mapped to home")
    }
}
