package thro.api

import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Tell THRØ (PD-119): a sentence on the secretary's desk becomes a typed act to confirm. A System One model is asked,
 * in one request, which act the sentence is and every argument each act could take — closed sets built from the
 * season's own fixtures and teams, and candidates code has already found in the text — and code reads only what the
 * chosen act needs. The model never does the calendar or the arithmetic; code does, and a person confirms.
 *
 * The model here is a stand-in that answers by inspecting the questions it was asked, which is what lets the test hold
 * the *questions* — every fixture offered, the scoreline candidates found — as well as the reading of the answers.
 */
class UnderstandingTest {

    private val today = LocalDate.of(2026, 9, 15)   // a Tuesday
    private val riverside = UUID.randomUUID(); private val grange = UUID.randomUUID(); private val dolphin = UUID.randomUUID()
    private val f1 = UUID.randomUUID(); private val f2 = UUID.randomUUID(); private val f3 = UUID.randomUUID()
    private val desk = Understanding.Desk(
        fixtures = listOf(
            Understanding.Fixture(f1, "Dolphin", dolphin, "Grange A", grange, Instant.parse("2026-10-08T19:00:00Z"), decided = false),
            Understanding.Fixture(f2, "Riverside A", riverside, "Grange A", grange, Instant.parse("2026-10-15T19:00:00Z"), decided = false),
            Understanding.Fixture(f3, "Riverside A", riverside, "Dolphin", dolphin, Instant.parse("2026-09-10T19:00:00Z"), decided = true),
        ),
        teams = listOf(Understanding.Team(riverside, "Riverside A"), Understanding.Team(grange, "Grange A"), Understanding.Team(dolphin, "Dolphin")),
        seasonStart = LocalDate.of(2026, 9, 1), seasonEnd = LocalDate.of(2027, 5, 31),
    )

    /** A model that answers from the questions: it records them, and a test says what each answer is. */
    private class Stub(val answer: (questions: Map<String, Any?>) -> Map<String, Any?>) : SystemOne {
        var asked: Map<String, Any?> = emptyMap()
        var state: Map<String, Any?> = emptyMap()
        override fun answers(state: String, questions: String): Map<String, Any?>? {
            this.state = Json.parseObject(state); asked = Json.parseObject(questions)
            return answer(asked)
        }
    }

    private fun choice(option: String, p: Double) = mapOf("type" to "choice", "choice" to option, "probabilities" to mapOf(option to p), "confidence" to p)
    private fun noul(p: Double) = mapOf("type" to "noul", "noul" to p)
    @Suppress("UNCHECKED_CAST")
    private fun options(questions: Map<String, Any?>, id: String): Map<String, Any?> = (questions[id] as Map<String, Any?>)["criteria"] as Map<String, Any?>
    /** The option key whose description mentions every word given. */
    private fun keyOf(questions: Map<String, Any?>, id: String, vararg words: String): String =
        options(questions, id).entries.first { (_, v) -> words.all { w -> (v?.toString() ?: "").contains(w) } }.key

    @Test
    fun `a result in a sentence names the fixture, the scoreline and which side each number belongs to`() {
        val stub = Stub { q ->
            mapOf(
                "act" to choice("result", 0.95),
                "fixture" to choice(keyOf(q, "fixture", "Dolphin", "Grange A", "8 Oct"), 0.9),
                "score" to choice(keyOf(q, "score", "5-3"), 0.97),
                "first_number" to choice("away", 0.85),
                "winner" to choice("away", 0.9),
            )
        }
        val u = Understanding(stub) { today }
        val read = u.understand(desk, "Grange A beat Dolphin 5-3 last night")
        assertNotNull(read)
        // The questions: every undecided fixture offered by name, side and date; the decided one too, for a correction.
        assertEquals(setOf("f1", "f2", "f3"), options(stub.asked, "fixture").keys - "none")
        assertTrue(options(stub.asked, "fixture")["f1"].toString().contains("Dolphin (home) v Grange A (away)"), options(stub.asked, "fixture")["f1"].toString())
        assertTrue(options(stub.asked, "fixture")["f1"].toString().contains("Thu 8 Oct 2026"))
        assertEquals(setOf("s1", "none"), options(stub.asked, "score").keys, "one scoreline found in the text, and the way out")
        assertEquals("Grange A beat Dolphin 5-3 last night", stub.state["text"])
        // The reading: the numbers go to the sides the model said, the winner agrees, and the least certain part sets the confidence.
        assertEquals("result", read.act)
        assertEquals(f1, read.fixture?.fixtureId)
        assertEquals(3, read.result?.legsHome); assertEquals(5, read.result?.legsAway)
        assertEquals(0.85, read.confidence, 1e-9)
        assertTrue(read.ready)
        assertEquals("Dolphin 3–5 Grange A, Thu 8 Oct", read.say)
        assertNull(read.doubt)
    }

    @Test
    fun `a winner that contradicts the numbers is a doubt, never a quiet guess`() {
        val stub = Stub { q ->
            mapOf("act" to choice("result", 0.95), "fixture" to choice("f1", 0.9), "score" to choice(keyOf(q, "score", "5-3"), 0.9),
                  "first_number" to choice("home", 0.8), "winner" to choice("away", 0.9))
        }
        val read = Understanding(stub) { today }.understand(desk, "Grange A beat Dolphin 5-3")!!
        assertEquals(5, read.result?.legsHome); assertEquals(3, read.result?.legsAway)
        assertEquals("score", read.doubt)
        assertFalse(read.ready)
    }

    @Test
    fun `a result with no numbers in it is not ready, and says what is missing`() {
        val stub = Stub { mapOf("act" to choice("result", 0.9), "fixture" to choice("f1", 0.9), "score" to choice("none", 0.99), "first_number" to choice("home", 0.5), "winner" to choice("away", 0.9)) }
        val read = Understanding(stub) { today }.understand(desk, "Grange beat Dolphin")!!
        assertEquals(setOf("none"), options(stub.asked, "score").keys, "no scoreline in the text, so the only option is none")
        assertNull(read.result)
        assertEquals("score", read.doubt)
        assertFalse(read.ready)
    }

    @Test
    fun `an award names the side it goes to, and carries the sentence as its reason`() {
        val stub = Stub { mapOf("act" to choice("award", 0.88), "fixture" to choice("f2", 0.92), "award_to" to choice("home", 0.9), "score" to choice("none", 0.9), "first_number" to choice("home", 0.5), "winner" to choice("home", 0.6)) }
        val read = Understanding(stub) { today }.understand(desk, "Walkover to Riverside on the 15th, Grange didn't turn up")!!
        assertEquals("award", read.act)
        assertEquals(riverside, read.award?.toTeamId)
        assertEquals("Walkover to Riverside on the 15th, Grange didn't turn up", read.award?.reason)
        assertEquals(0.88, read.confidence, 1e-9)
        assertTrue(read.ready)
        assertEquals("Riverside A v Grange A, Thu 15 Oct — awarded to Riverside A", read.say)
    }

    @Test
    fun `a new fixture reads two teams, a relative day and a time, and code does the calendar`() {
        val stub = Stub { q ->
            mapOf(
                "act" to choice("schedule", 0.9),
                "home_team" to choice(keyOf(q, "home_team", "Riverside A"), 0.9),
                "away_team" to choice(keyOf(q, "away_team", "Dolphin"), 0.9),
                "date_mode" to choice("relative", 0.9), "day_anchor" to choice("weekday", 0.9), "weekday" to choice("Thursday", 0.95), "week_offset" to choice("next", 0.7),
                "month" to choice("none", 0.9), "day" to choice("none", 0.9),
                "time" to choice(keyOf(q, "time", "8"), 0.8),
            )
        }
        val read = Understanding(stub) { today }.understand(desk, "Add Riverside A v Dolphin next Thursday at 8")!!
        assertEquals("schedule", read.act)
        assertEquals(riverside, read.schedule?.homeTeamId); assertEquals(dolphin, read.schedule?.awayTeamId)
        // Tuesday 15 September; "next Thursday" is the Thursday of the following week, 24 September; "8" in the
        // evening, because darts is played in the evening — 20:00 in London is 19:00Z in September.
        assertEquals(Instant.parse("2026-09-24T19:00:00Z"), read.schedule?.scheduledAt)
        assertEquals(0.7, read.confidence, 1e-9)
        assertTrue(read.ready)
        assertEquals("Riverside A v Dolphin, Thu 24 Sep, 8:00 pm", read.say)
    }

    @Test
    fun `an absolute date is read as its parts, and a date outside the season is a doubt`() {
        val stub = Stub { q ->
            mapOf("act" to choice("schedule", 0.9), "home_team" to choice(keyOf(q, "home_team", "Grange A"), 0.9), "away_team" to choice(keyOf(q, "away_team", "Riverside A"), 0.9),
                  "date_mode" to choice("absolute", 0.9), "day_anchor" to choice("today", 0.3), "weekday" to choice("Monday", 0.2), "week_offset" to choice("this", 0.5),
                  "month" to choice("June", 0.9), "day" to choice("3", 0.9), "time" to choice("none", 0.9))
        }
        val read = Understanding(stub) { today }.understand(desk, "Grange A v Riverside A on 3 June")!!
        // No year stated: the first 3 June on or after today, which is 2027 — outside the season, so a doubt.
        assertEquals(LocalDate.of(2027, 6, 3), read.schedule?.on)
        assertEquals("date", read.doubt)
        assertFalse(read.ready)
    }

    @Test
    fun `a fixture is moved to a day and a time, and with no time stated it keeps its own`() {
        val dated = Stub { q ->
            mapOf("act" to choice("move", 0.92), "fixture" to choice("f2", 0.9),
                  "date_mode" to choice("relative", 0.9), "day_anchor" to choice("weekday", 0.9), "weekday" to choice("Thursday", 0.95), "week_offset" to choice("next", 0.8),
                  "month" to choice("none", 0.9), "day" to choice("none", 0.9), "time" to choice(keyOf(q, "time", "8.30"), 0.85))
        }
        val read = Understanding(dated) { today }.understand(desk, "Move Riverside v Grange to next Thursday at 8.30")!!
        assertEquals("move", read.act)
        assertEquals(f2, read.fixture?.fixtureId)
        assertEquals(Instant.parse("2026-09-24T19:30:00Z"), read.move?.to)
        assertEquals("Riverside A v Grange A, Thu 15 Oct → Thu 24 Sep, 8:30 pm", read.say)
        assertEquals(0.8, read.confidence, 1e-9)
        assertTrue(read.ready)

        // No time in the sentence: the fixture keeps the clock time it had — eight in the evening in London.
        val undated = Stub { mapOf("act" to choice("move", 0.9), "fixture" to choice("f2", 0.9), "date_mode" to choice("absolute", 0.9), "day_anchor" to choice("today", 0.2),
                                   "weekday" to choice("none", 0.9), "week_offset" to choice("this", 0.5), "month" to choice("November", 0.9), "day" to choice("5", 0.9), "time" to choice("none", 0.95)) }
        val kept = Understanding(undated) { today }.understand(desk, "Riverside v Grange is postponed to 5 November")!!
        assertEquals(Instant.parse("2026-11-05T20:00:00Z"), kept.move?.to, "20:00 in London, which in November is 20:00Z")
        assertTrue(kept.ready)

        // A fixture that has a result is not moved; and a move with no date is a doubt.
        val played = Stub { mapOf("act" to choice("move", 0.9), "fixture" to choice("f3", 0.9), "date_mode" to choice("none", 0.9), "time" to choice("none", 0.9)) }
        val refused = Understanding(played) { today }.understand(desk, "Move Riverside v Dolphin")!!
        assertEquals("fixture", refused.doubt); assertFalse(refused.ready)
        val nowhere = Stub { mapOf("act" to choice("move", 0.9), "fixture" to choice("f2", 0.9), "date_mode" to choice("none", 0.9), "time" to choice("none", 0.9)) }
        assertEquals("date", Understanding(nowhere) { today }.understand(desk, "Riverside v Grange is off")!!.doubt)
    }

    @Test
    fun `a question is not an act, and the reading says so`() {
        val stub = Stub { mapOf("act" to choice("none", 0.9)) }
        val read = Understanding(stub) { today }.understand(desk, "How many games are left?")!!
        assertEquals("none", read.act)
        assertFalse(read.ready)
        assertTrue(read.say.contains("not something THRØ can do from here"), read.say)
    }

    @Test
    fun `a model with no answer is no reading`() {
        val stub = Stub { throw IllegalStateException("down") }
        assertNull(Understanding(stub) { today }.understand(desk, "Grange A beat Dolphin 5-3"))
        val silent = object : SystemOne { override fun answers(state: String, questions: String): Map<String, Any?>? = null }
        assertNull(Understanding(silent) { today }.understand(desk, "Grange A beat Dolphin 5-3"))
    }

    @Test
    fun `the scoreline and time candidates are found by code, so the model can only choose what is there`() {
        assertEquals(listOf("5-3"), Understanding.scorelines("Grange A beat Dolphin 5-3 last night"))
        assertEquals(listOf("7–2", "4-4"), Understanding.scorelines("first leg 7–2, then 4-4, on Thursday 8"))
        assertEquals(listOf("8", "20:30"), Understanding.times("at 8 or maybe 20:30 on the 15th"))
        assertEquals(listOf("7.30pm"), Understanding.times("7.30pm start"))
        assertEquals(emptyList(), Understanding.times("Grange A beat Dolphin 5-3"))
    }
}
