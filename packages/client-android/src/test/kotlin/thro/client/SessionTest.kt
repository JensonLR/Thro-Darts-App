package thro.client

import thro.journal.DeviceId
import thro.journal.Journal
import thro.journal.Seat
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/// A match, scored (PD-083, PD-084).
///
/// **These run against a real journal**, in a temp file, on the JVM's own copy of the same SQLite the phone
/// uses — which is possible precisely because the Android client did not get a second implementation. So the
/// engine-journal-screen order, the retraction, and picking a match back up are all exercised for real here,
/// and what the emulator adds is a screen rather than a fact.
class SessionTest {

    private val directory = Files.createTempDirectory("thro-android-test")
    private val journal = Journal.open(
        directory.resolve("journal.sqlite").toString(), DeviceId("android-tests"),
    )

    @AfterTest fun tidy() {
        directory.toFile().deleteRecursively()
    }

    private fun match() = ThroSession.start(journal, "Jenson", "Ethan")

    @Test fun `a visit the engine accepts is written and then shown`() {
        val session = match()
        session.enter(180)
        assertEquals(321, session.remaining(Seat.HOME))
        assertEquals(1, journal.entries(session.matchId).size, "and it is in the journal, not only on screen")
    }

    @Test fun `a visit the engine refuses is not written at all`() {
        // 179 is not three darts. The screen says why and the record stays clean — a refusal that still
        // wrote a row would be a record of something nobody threw.
        val session = match()
        session.enter(179)
        assertEquals(501, session.remaining(Seat.HOME))
        assertTrue(session.mark is ThroMark.Refused)
        assertEquals(0, journal.entries(session.matchId).size)
    }

    @Test fun `undo is a retraction and the board is rebuilt by replaying`() {
        val session = match()
        session.enter(180)
        session.undo()
        assertEquals(501, session.remaining(Seat.HOME), "the score goes back")
        assertEquals(2, journal.entries(session.matchId).size,
                     "and the journal has both the visit and the retraction — nothing was deleted")
    }

    @Test fun `a match in progress is offered back and comes back by replay`() {
        val session = match()
        session.enter(180)
        session.enter(140)

        val offered = ThroSession.resumable(journal)
        assertNotNull(offered)
        assertEquals(session.matchId, offered.id)

        val carried = ThroSession.resume(journal, offered)
        assertEquals(321, carried.remaining(Seat.HOME))
        assertEquals(361, carried.remaining(Seat.AWAY))
    }

    @Test fun `a finished match is not offered back`() {
        val session = match()
        // Best of five, so first to three legs. Five rounds of 180, 180, 180, 180, 141 wins a leg for
        // whoever started it, and the starter alternates — so the legs go 1-0, 1-1, 2-1, 2-2, 3-2 and the
        // match is decided on the last visit of the fifth. The same sequence was played on the emulator and
        // came out 3-2, which is why it is written as a sequence rather than as a loop with a condition.
        repeat(5) {
            if (session.state.winner == null) {
                repeat(4) { session.enter(180) }
                session.enter(141)
            }
        }
        assertNotNull(session.state.winner, "the match should be won")
        assertEquals(3, session.legs(Seat.HOME))
        assertEquals(2, session.legs(Seat.AWAY))
        assertEquals("Jenson wins", ThroResultWords.winner(session))
        assertEquals("3–2", ThroResultWords.scoreline(session))
        assertNull(ThroSession.resumable(journal), "a won match is not something to carry on with")
    }

    // MARK: what a result says

    @Test fun `the scoreline is home first whoever won`() {
        // A scoreline whose order changes with the result is a scoreline nobody can read at a glance.
        val session = match()
        assertEquals("0–0", ThroResultWords.scoreline(session))
        assertEquals("3–2", ThroResultWords.scoreline(wonMatch()))
    }

    // MARK: PD-011, who stands behind the result

    private fun wonMatch(): ThroSession {
        val session = match()
        repeat(5) {
            if (session.state.winner == null) { repeat(4) { session.enter(180) }; session.enter(141) }
        }
        return session
    }

    @Test fun `a result starts self-reported because nobody has said anything`() {
        assertEquals(ThroVerification.SELF_REPORTED, ThroResultWords.label(wonMatch()))
    }

    @Test fun `both agreeing is two people and the sentence says so`() {
        val session = wonMatch()
        session.attest(Seat.HOME, agrees = true)
        assertEquals(ThroVerification.SELF_REPORTED, ThroResultWords.label(session),
                     "one is not both — a single confirmation claims nothing")
        // ...and the sentence says which of them, because "nobody has confirmed it" stopped being true
        // the moment one of them did.
        val halfway = ThroResultWords.verified(session)
        assertTrue(halfway.startsWith("Jenson has confirmed this and Ethan has not"), halfway)
        assertFalse(halfway.contains("nobody"), halfway)

        session.attest(Seat.AWAY, agrees = true)
        assertEquals(ThroVerification.BOTH_CONFIRMED, ThroResultWords.label(session))
        val said = ThroResultWords.verified(session)
        assertTrue(said.contains("Two people agreeing, not two devices"),
                   "the honest limit of what one phone can witness")
    }

    @Test fun `a contest outranks a confirmation whichever came first`() {
        // A result one competitor does not accept is disputed whatever the other said. Both orders,
        // because "the last one wins" would make the label depend on who reached for the phone.
        val first = wonMatch()
        first.attest(Seat.HOME, agrees = true)
        first.attest(Seat.AWAY, agrees = false)
        assertEquals(ThroVerification.DISPUTED, ThroResultWords.label(first))

        val second = wonMatch()
        second.attest(Seat.HOME, agrees = false)
        second.attest(Seat.AWAY, agrees = true)
        assertEquals(ThroVerification.DISPUTED, ThroResultWords.label(second))
    }

    @Test fun `an agreement a later change overtakes stops counting`() {
        // What was agreed is no longer what is recorded. Falling back to self-reported is the conservative
        // answer; going on saying "both confirmed" would be claiming an agreement nobody gave to THIS
        // version of the result.
        val session = wonMatch()
        session.attest(Seat.HOME, agrees = true)
        session.attest(Seat.AWAY, agrees = true)
        assertEquals(ThroVerification.BOTH_CONFIRMED, ThroResultWords.label(session))

        session.undo()
        assertEquals(ThroVerification.SELF_REPORTED, ThroResultWords.label(session),
                     "a retraction after the agreement makes it stale, and stale is not confirmed")
    }

    @Test fun `nothing about an attestation is deleted`() {
        val session = wonMatch()
        val before = journal.entries(session.matchId).size
        session.attest(Seat.HOME, agrees = true)
        session.attest(Seat.HOME, agrees = false)
        assertTrue(journal.entries(session.matchId).size > before,
                   "changing your mind appends; it does not rewrite what you said")
    }

    @Test fun `a result says it is self-reported and claims nothing more`() {
        // PD-011's confirmation is on iOS and not here. Saying "confirmed" would be the app claiming
        // something nobody did, on the largest figure the product produces.
        val said = ThroResultWords.verified(wonMatch()).lowercase()
        assertTrue(said.contains("self-reported"))
        assertTrue(said.contains("nobody has confirmed"))
    }
}
