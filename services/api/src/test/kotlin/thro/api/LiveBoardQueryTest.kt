package thro.api

import java.sql.Connection
import java.time.Instant
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import thro.engine.Dart
import thro.engine.InRule
import thro.engine.MatchFormat
import thro.engine.OutRule
import thro.engine.Structure
import thro.engine.StructureMode

/**
 * The live board, run — not only the consent it asks (V060).
 *
 * `LiveBoardTest` holds the consent rules and never ran the board's query, and the query had never
 * parsed: it named two columns V018 had removed, and read two projections nothing writes. So every
 * season's `/live` answered 500 and the pub screen's "Playing now" never showed a game. These tests
 * drive a real season, a real fixture and real visits through the command path and read the board.
 */
class LiveBoardQueryTest {
    private val configured = TestDatabase.configured
    private fun migrated(): Connection = TestDatabase.migrated()
    private val t0: Instant = Instant.parse("2026-09-01T19:00:00Z")

    private class Night(val c: Connection, val season: UUID, val fixture: UUID, val match: UUID,
                        val home: UUID, val away: UUID, val device: UUID = UUID.randomUUID()) {
        var seq = 0L
        fun visit(seat: String, total: Int? = null, darts: List<Dart>? = null) {
            val result = CommandHandler(c).handle(
                VisitCommand(
                    commandId = UUID.randomUUID(), matchId = match, deviceId = device, deviceSeq = seq + 1,
                    actorId = home, actorRole = "participant", correlationId = UUID.randomUUID(),
                    player = seat, visitTotal = total, dartsUsed = null,
                    occurredAt = "2026-09-24T19:00:00Z", occurredTz = "Europe/London", darts = darts,
                ),
            )
            assertTrue(result is CommandResult.Applied, "not applied: $result")
            seq += 1
        }
        fun board() = LiveBoard(c).inPlay(season)
    }

    private fun night(c: Connection, format: MatchFormat? = null): Night {
        val orgs = Organisations(c)
        val admin = orgs.createPlayer()
        val league = orgs.createLeague("Teesside Thursday", "Teesside", by = admin)
        val season = orgs.openSeason(league, "2026/27", LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))
        val division = orgs.createDivision(season, "Division One", 1)
        val teams = listOf("Grange A", "Riverside A").map { orgs.createTeam(it, "Stockton", by = admin) }
        for (t in teams) orgs.acceptAffiliation(orgs.affiliate(t, season, division, from = t0, by = admin), at = t0)
        val fixture = orgs.scheduleFixture(season, division, teams[0], teams[1], at = t0.plus(7, ChronoUnit.DAYS), by = admin)
        val home = orgs.createPlayer()
        val away = orgs.createPlayer()
        val match = UUID.randomUUID()
        Matches(c).open(match, home, away, format ?: playtestFormat())
        orgs.citeMatch(fixture, match)
        return Night(c, season, fixture, match, home, away)
    }

    @Test
    fun `a season with nothing in play reads as nothing, not as an error`() {
        if (!configured) return
        migrated().use { c ->
            // The query this replaced failed to parse, so even an empty season was a 500.
            assertEquals(emptyList(), LiveBoard(c).inPlay(UUID.randomUUID()))
        }
    }

    @Test
    fun `a game being thrown is on the board with the scores the engine replays`() {
        if (!configured) return
        migrated().use { c ->
            val n = night(c)
            assertEquals(emptyList(), n.board(), "cited, but nobody has thrown: not a game in play")
            n.visit("home", 180)
            n.visit("away", 60)
            val panel = n.board().single()
            assertEquals(321, panel.homeRemaining)
            assertEquals(441, panel.awayRemaining)
            assertEquals(0, panel.homeLegs)
            assertEquals("home", panel.thrower)
            assertTrue(panel.teamsOnly, "nobody has said a live screen may name them")
        }
    }

    @Test
    fun `a leg just won shows the next leg, not the last visit of the old one`() {
        if (!configured) return
        migrated().use { c ->
            val short = MatchFormat(
                startingScore = 40, inRule = InRule.STRAIGHT, outRule = OutRule.DOUBLE,
                legs = Structure(StructureMode.FIRST_TO, 3), throwFirst = Seat.home,
            )
            val n = night(c, short)
            n.visit("home", darts = listOf(Dart.parse("D20")!!))
            val panel = n.board().single()
            // The old query took each player's latest visit across legs, so the winner showed 0 and the
            // other player their score from a leg that was over.
            assertEquals(40, panel.homeRemaining)
            assertEquals(40, panel.awayRemaining)
            assertEquals(1, panel.homeLegs)
            assertEquals("away", panel.thrower, "the next leg's starter")
        }
    }

    @Test
    fun `a result recorded, or a match won, takes the game off the board`() {
        if (!configured) return
        migrated().use { c ->
            val n = night(c, MatchFormat(
                startingScore = 40, inRule = InRule.STRAIGHT, outRule = OutRule.DOUBLE,
                legs = Structure(StructureMode.FIRST_TO, 1), throwFirst = Seat.home,
            ))
            n.visit("home", darts = listOf(Dart.parse("D20")!!))
            assertEquals(emptyList(), n.board(), "won is not playing, whether or not the secretary has typed it in yet")
        }
    }

    @Test
    fun `a player is named only where they said a live screen may`() {
        if (!configured) return
        migrated().use { c ->
            val n = night(c)
            val ann = UUID.randomUUID()
            c.createStatement().use { st ->
                st.execute("INSERT INTO identity.account (account_id, display_name, age_band, age_assurance) " +
                           "VALUES ('$ann', 'Ann Walsh', 'adult', 'self_declared')")
                st.execute("INSERT INTO identity.player_claim (claim_id, account_id, player_id, method) " +
                           "VALUES ('${UUID.randomUUID()}', '$ann', '${n.home}', 'self_created')")
            }
            n.visit("home", 60)
            assertNull(n.board().single().homeName, "claimed but not agreed: no name")
            Consent(c).say(ann, Consent.Scope.LIVE, yes = true)
            val panel = n.board().single()
            assertEquals("Ann Walsh", panel.homeName)
            assertNull(panel.awayName)
        }
    }
}
