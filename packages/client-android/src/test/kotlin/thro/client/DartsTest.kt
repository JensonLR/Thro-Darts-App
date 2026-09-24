package thro.client

import thro.engine.BustReason
import thro.engine.BustRule
import thro.engine.Dart
import thro.engine.RejectionReason
import thro.engine.Ring
import thro.journal.DeviceId
import thro.journal.Journal
import thro.journal.NewMatch
import thro.journal.Seat
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/// A visit entered dart by dart (OD-023), against a real journal — the same shape as `SessionTest`, because the
/// claim is about what reaches the record, not what a screen draws.
class DartsTest {

    private val directory = Files.createTempDirectory("thro-android-darts")
    private val journal = Journal.open(directory.resolve("journal.sqlite").toString(), DeviceId("android-tests"))

    @AfterTest fun tidy() {
        directory.toFile().deleteRecursively()
    }

    private fun match(rule: BustRule = BustRule.RESTORE_VISIT) =
        ThroSession.start(journal, NewMatch(homeName = "Jenson", awayName = "Ethan", bustRule = rule))

    private fun t(n: Int) = Dart(n, Ring.TREBLE)
    private fun d(n: Int) = Dart(n, Ring.DOUBLE)
    private fun s(n: Int) = Dart(n, Ring.SINGLE)

    /// Home to [left] by totals, with the away player missing every visit, so it is home's throw again.
    private fun homeOn(session: ThroSession, left: Int) {
        var toGo = 501 - left
        while (toGo > 0) {
            val visit = minOf(180, toGo).let { if (toGo - it in 1..1) it - 1 else it }
            session.total(visit)
            toGo -= visit
            session.total(0)
        }
        assertEquals(left, session.remaining(Seat.HOME))
        assertEquals(Seat.HOME, session.throwerSeat)
    }

    @Test fun `darts are recorded as darts and the match replays from them`() {
        val session = match()
        listOf(t(20), t(20), t(20)).forEach(session::dart)
        session.enterDarts()
        assertEquals(321, session.remaining(Seat.HOME))
        val written = journal.entries(session.matchId).single()
        assertEquals(listOf(t(20), t(20), t(20)), written.darts, "the darts themselves, not only their total")
        assertEquals(180, written.visitTotal)

        val (state, visits) = journal.replayVisits(session.matchId)
        assertEquals(321, state.remaining[Seat.HOME.playerId])
        assertEquals(listOf(t(20), t(20), t(20)), visits.single().darts)
        assertTrue(session.darts.isEmpty(), "the hand is empty once it is written")
    }

    @Test fun `T20 from 60 is recorded as the bust it is`() {
        // A total of 60 from 60 reads as a checkout; only the darts can show it ended on a treble.
        val session = match()
        homeOn(session, 60)
        val before = journal.entries(session.matchId).size
        session.dart(t(20))
        assertTrue(session.visitDecided, "the visit is over after one dart")
        assertTrue(ThroScoringWords.say(session, "").startsWith("Bust."))
        session.enterDarts()

        val mark = session.mark
        assertTrue(mark is ThroMark.Bust, "$mark")
        assertEquals(BustReason.NOT_A_FINISHING_DART, mark.reason)
        assertEquals(60, session.remaining(Seat.HOME))
        assertEquals(Seat.AWAY, session.throwerSeat)
        assertEquals(before + 1, journal.entries(session.matchId).size, "recorded, not refused")
        assertEquals(listOf(t(20)), journal.entries(session.matchId).last().darts)
        val said = ThroScoringWords.say(session, "")
        assertTrue(said.contains("T20 reaches zero, and this leg has to end on a double."), said)
        assertTrue(said.contains("Score restored to 60."), said)
        assertTrue(said.contains("Ethan to throw."), said)
    }

    @Test fun `the route follows the darts in hand`() {
        val session = match()
        homeOn(session, 100)
        session.dart(t(20))
        assertEquals(40, session.throwerLeft)
        assertEquals(listOf("D20"), session.throwerRoute, "D20 with two darts left, from the engine's table")
        assertEquals("D20", ThroScoringWords.say(session, ""))

        session.takeBackDarts(0)
        session.dart(s(20))
        session.dart(s(20))
        assertEquals(60, session.throwerLeft)
        assertEquals(1, session.dartsLeftInHand)
        assertEquals(emptyList(), session.throwerRoute, "60 is not a one-dart finish, so nothing is offered")
        assertEquals("", ThroScoringWords.say(session, ""))
    }

    @Test fun `under keep-scored darts 20 then D15 from 40 leaves 20`() {
        val session = match(BustRule.KEEP_SCORED_DARTS)
        homeOn(session, 40)
        session.dart(s(20))
        session.dart(d(15))
        assertTrue(session.visitDecided)
        session.enterDarts()

        assertEquals(20, session.remaining(Seat.HOME), "the 20 before the busting dart stands")
        val mark = session.mark
        assertTrue(mark is ThroMark.Bust, "$mark")
        assertEquals(20, mark.restored, "the engine's score, not the one the visit began on")
        val said = ThroScoringWords.say(session, "")
        assertTrue(said.contains("D15 goes below zero. The 20 before it stands."), said)
        assertTrue(said.contains("Score now 20."), said)
        assertFalse(said.contains("40"), said)
    }

    @Test fun `a dart after a decided visit is not taken`() {
        // A stray tap after a checkout would otherwise turn it into a bust.
        val session = match()
        homeOn(session, 40)
        session.dart(d(20))
        assertTrue(session.visitDecided)
        session.dart(t(20))
        assertEquals(listOf(d(20)), session.darts, "the stray dart is refused")
        assertEquals(ThroMark.AlreadyDecided, session.mark)
        assertEquals(ThroScoringWords.VISIT_ALREADY_DECIDED, ThroScoringWords.say(session, ""))

        session.enterDarts()
        assertEquals(1, session.legs(Seat.HOME))
        assertEquals(ThroMark.LegWon(Seat.HOME), session.mark, "from the engine's effect, not a guess")
        assertTrue(ThroScoringWords.say(session, "").startsWith("Leg to Jenson, 1–0."))
    }

    @Test fun `a busting total under keep-scored darts asks for the darts`() {
        val session = match(BustRule.KEEP_SCORED_DARTS)
        homeOn(session, 40)
        val before = journal.entries(session.matchId).size
        session.total(50)
        assertEquals(ThroMark.Refused(RejectionReason.DARTS_REQUIRED, 50), session.mark)
        assertEquals(
            "That is a bust, and this match keeps the darts before a bust. Enter this visit dart by dart.",
            ThroScoringWords.say(session, ""),
        )
        assertEquals(before, journal.entries(session.matchId).size, "nothing is written")
        assertEquals(40, session.remaining(Seat.HOME))
    }

    @Test fun `a busting total under the standard rule says the score it went back to`() {
        val session = match()
        homeOn(session, 60)
        session.total(61)
        val said = ThroScoringWords.say(session, "")
        assertTrue(said.startsWith("Bust."), said)
        assertTrue(said.contains("Score restored to 60."), said)
    }

    @Test fun `Enter says how many darts are still to come`() {
        val session = match()
        assertEquals("Enter", ThroScoringWords.enterLabel(session))
        session.dart(t(20))
        assertEquals("2 more", ThroScoringWords.enterLabel(session))
        assertFalse(session.dartsMayBeEntered)
        session.enterDarts()
        assertEquals(0, journal.entries(session.matchId).size, "a hand that is not finished is not entered")
        session.dart(t(20)); session.dart(s(5))
        assertEquals("Enter 125", ThroScoringWords.enterLabel(session))
    }

    @Test fun `undo after a darts visit replays the darts that remain`() {
        val session = match()
        listOf(t(20), t(20), t(20)).forEach(session::dart)
        session.enterDarts()
        session.undo()
        assertEquals(501, session.remaining(Seat.HOME))
        assertNull(journal.replayVisits(session.matchId).second.firstOrNull())
    }

    @Test fun `half-entered darts survive being stored and read back`() {
        val darts = listOf(t(20), Dart.OUTER_BULL, Dart.BULL)
        assertEquals(darts, ThroDartWords.read(ThroDartWords.store(darts)))
        assertEquals(emptyList(), ThroDartWords.read(""))
        assertEquals(listOf(t(20)), ThroDartWords.read("T20,T25,nonsense"), "what is not a dart is dropped")

        val session = match()
        session.restoreDarts(darts)
        assertEquals(darts, session.darts)
    }

    @Test fun `every key has words for TalkBack`() {
        assertEquals("double 16", ThroDartWords.spoken(d(16)))
        assertEquals("treble 20", ThroDartWords.spoken(t(20)))
        assertEquals("single 5", ThroDartWords.spoken(s(5)))
        assertEquals("bullseye", ThroDartWords.spoken(Dart.BULL))
        assertEquals("twenty five", ThroDartWords.spoken(Dart.OUTER_BULL))
        assertEquals("miss", ThroDartWords.spoken(Dart.MISS))
        assertEquals(listOf(20, 19, 18, 17, 16), ThroDartWords.rows.first())
        assertEquals(listOf(5, 4, 3, 2, 1), ThroDartWords.rows.last())
    }

    @Test fun `a keep-scored-darts match opens on the dart keypad`() {
        assertEquals(ThroEntryMode.DARTS, ThroEntryMode.initial(ThroEntryMode.TOTAL, BustRule.KEEP_SCORED_DARTS))
        assertEquals(ThroEntryMode.TOTAL, ThroEntryMode.initial(null, BustRule.RESTORE_VISIT))
        assertEquals(ThroEntryMode.DARTS, ThroEntryMode.initial(ThroEntryMode.DARTS, BustRule.RESTORE_VISIT))
    }

    @Test fun `the setup screen's choices reach the match`() {
        val match = ThroSetupWords.match(" Jenson ", "Ethan", 301, 3, Seat.AWAY, BustRule.KEEP_SCORED_DARTS)
        val session = ThroSession.start(journal, match)
        assertEquals(301, session.remaining(Seat.HOME))
        assertEquals(Seat.AWAY, session.throwerSeat)
        assertEquals(BustRule.KEEP_SCORED_DARTS, journal.match(session.matchId).bustRule)
        assertEquals(3, journal.match(session.matchId).legsTarget)
        assertEquals("Jenson", session.homeName)
        assertEquals("Bust: back to the start of the visit (standard)", ThroSetupWords.bustRule(BustRule.RESTORE_VISIT))
        assertEquals("Bust: keep the darts before the bust (some pub leagues)",
                     ThroSetupWords.bustRule(BustRule.KEEP_SCORED_DARTS))
        assertEquals("Player two", ThroSetupWords.seatName(Seat.AWAY, "Jenson", " "))
    }

    // ---------------------------------------------------------------- PD-001 on Android

    @Test fun `a total that checks out asks darts used, then darts at a double, and records both`() {
        val session = match()
        homeOn(session, 40)
        session.enter(40)
        assertEquals(ThroSession.Prompt.DartsUsed(40), session.prompt, "nothing written before the questions")
        session.answer(2)
        assertEquals(ThroSession.Prompt.DartsAtDouble(40, 2, finished = true), session.prompt)
        assertEquals(listOf(1, 2), session.prompt!!.options, "no more darts at a double than darts used")
        session.answer(1)
        assertEquals(null, session.prompt)
        val row = journal.entries(session.matchId).last()
        assertEquals(2, row.dartsUsed)
        assertEquals(1, row.dartsAtDouble)
    }

    @Test fun `a total from a finish that misses asks darts at a double, and not sure is unknown`() {
        val session = match()
        homeOn(session, 40)
        session.enter(20)
        assertEquals(ThroSession.Prompt.DartsAtDouble(20, null, finished = false), session.prompt)
        assertEquals(listOf(0, 1, 2, 3), session.prompt!!.options)
        session.answer(null)
        assertEquals(null, journal.entries(session.matchId).last().dartsAtDouble, "unknown, never zero")
        assertEquals(20, session.remaining(Seat.HOME))
    }

    @Test fun `a total from nowhere near a finish asks nothing`() {
        val session = match()
        session.enter(60)
        assertEquals(null, session.prompt)
        assertEquals(441, session.remaining(Seat.HOME))
    }

    @Test fun `going back from the question writes nothing`() {
        val session = match()
        homeOn(session, 40)
        val before = journal.entries(session.matchId).size
        session.enter(40)
        session.cancelPrompt()
        assertEquals(before, journal.entries(session.matchId).size)
        assertEquals(40, session.remaining(Seat.HOME))
    }
}
