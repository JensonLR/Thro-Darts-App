package thro.api

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Paste the fixture list (PD-122). A league's season is ninety lines somebody already typed once — on a sheet, in an
 * email, on a web page — and typing them again into boxes is the first evening a secretary spends with THRØ. So the
 * desk takes the list as it is written. Each line is one request to the System One model: is this a fixture, which of
 * the season's teams is at home and which away, which month and day, which of the times code found. Code does the
 * rest: a date heading carries down to the fixtures beneath it, the year is the one that puts the date inside the
 * season, a fixture with no time takes the list's usual one, and every row comes back with its doubt named for a
 * person to confirm. Nothing is scheduled by reading.
 */
class FixtureListTest {

    private val riverside = UUID.randomUUID(); private val grange = UUID.randomUUID(); private val dolphin = UUID.randomUUID(); private val bell = UUID.randomUUID()
    private val desk = Understanding.Desk(
        fixtures = emptyList(),
        teams = listOf(Understanding.Team(riverside, "Riverside A"), Understanding.Team(grange, "Grange A"), Understanding.Team(dolphin, "Dolphin"), Understanding.Team(bell, "Bell B")),
        seasonStart = LocalDate.of(2026, 9, 1), seasonEnd = LocalDate.of(2027, 5, 31),
    )
    private val months = listOf("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December")

    /** A stand-in that reads a line the way the model would: teams by the first word of their names, in the order they appear. */
    private inner class Reader : SystemOne {
        val lines: MutableList<String> = java.util.Collections.synchronizedList(mutableListOf())   // six lines are read at a time
        override fun answers(state: String, questions: String): Map<String, Any?>? {
            val line = Json.parseObject(state)["line"] as String
            lines += line
            val q = Json.parseObject(questions)
            @Suppress("UNCHECKED_CAST")
            fun options(id: String) = (q[id] as Map<String, Any?>)["criteria"] as Map<String, Any?>
            fun choice(option: String, p: Double) = mapOf("type" to "choice", "choice" to option, "probabilities" to mapOf(option to p), "confidence" to p)
            val named = options("home_team").filterKeys { it != "none" }
                .mapNotNull { (k, v) -> line.indexOf(v.toString().substringBefore(' '), ignoreCase = true).takeIf { it >= 0 }?.let { k to it } }.sortedBy { it.second }.map { it.first }
            val month = months.firstOrNull { line.contains(it.take(3), ignoreCase = true) }
            val day = Regex("""(?<![\d.:])(\d{1,2})(?:st|nd|rd|th)?\s+(?:[A-Za-z]{3,9})|(?:[A-Za-z]{3,9})\s+(\d{1,2})""").find(line)?.let { m -> m.groupValues[1].ifEmpty { m.groupValues[2] } }
            val time = options("time").entries.firstOrNull { it.key != "none" }?.key ?: "none"
            return mapOf(
                "is_fixture" to mapOf("type" to "noul", "noul" to if (line.contains(" v ")) 0.97 else 0.04),
                "home_team" to choice(named.getOrNull(0) ?: "none", 0.9), "away_team" to choice(named.getOrNull(1) ?: "none", 0.88),
                "month" to choice(month ?: "none", 0.95), "day" to choice(if (month != null && day != null) day else "none", 0.93),
                "time" to choice(time, 0.9),
            )
        }
    }

    private val pasted = """
        TEESSIDE THURSDAY LEAGUE — DIVISION A

        Thursday 8 October
        Riverside A v Grange A 7.30pm
        Dolphin v Bell B
        15 Oct - Grange A v Dolphin 8pm
        Week 3 (bye: Bell B)
        Riverside v Dolphin, 22nd October
        14 January: Bell B v Riverside A
    """.trimIndent()

    @Test
    fun `a pasted list becomes rows, with the date carried down, the year from the season and the usual time filled in`() {
        val reader = Reader()
        val read = Understanding(reader) { LocalDate.of(2026, 8, 20) }.readList(desk, pasted)
        assertNotNull(read)
        assertEquals(8, reader.lines.size, "one request per line that says anything — eight here; the blank one is not sent")

        val rows = read.rows
        assertEquals(listOf("Riverside A v Grange A", "Dolphin v Bell B", "Grange A v Dolphin", "Riverside A v Dolphin", "Bell B v Riverside A"), rows.map { "${it.home} v ${it.away}" })
        // The heading's date carries down to the two fixtures beneath it; "Riverside" is read as Riverside A.
        assertEquals(LocalDate.of(2026, 10, 8), rows[0].on); assertEquals(LocalDate.of(2026, 10, 8), rows[1].on)
        assertEquals(LocalDate.of(2026, 10, 15), rows[2].on); assertEquals(LocalDate.of(2026, 10, 22), rows[3].on)
        // January has no year on it: the one that falls inside the season is 2027.
        assertEquals(LocalDate.of(2027, 1, 14), rows[4].on)
        // A stated time is kept; a fixture with none takes the list's usual one — 7.30, stated first.
        assertEquals(LocalTime.of(19, 30), rows[0].time); assertEquals(LocalTime.of(20, 0), rows[2].time)
        assertEquals(LocalTime.of(19, 30), rows[1].time); assertEquals(LocalTime.of(19, 30), rows[4].time)
        assertEquals(Instant.parse("2026-10-08T18:30:00Z"), rows[0].scheduledAt, "7.30 in the evening in London, in October")
        assertEquals(Instant.parse("2027-01-14T19:30:00Z"), rows[4].scheduledAt)
        assertEquals(riverside, rows[3].homeTeamId); assertEquals(dolphin, rows[3].awayTeamId)
        assertTrue(rows.all { it.doubt == null }, rows.map { it.doubt }.toString())
        assertEquals(0.88, rows[0].confidence, 1e-9, "the least certain part read")
        assertEquals(4, rows[0].line, "the line as the person pasted it, counted from one")

        assertEquals(listOf("TEESSIDE THURSDAY LEAGUE — DIVISION A" to "not a fixture", "Thursday 8 October" to "a date, carried down", "Week 3 (bye: Bell B)" to "not a fixture"),
                     read.skipped.map { it.text to it.why })
    }

    @Test
    fun `a row says what is in doubt - a team THRØ does not have, a date outside the season, no time anywhere`() {
        val reader = Reader()
        val read = Understanding(reader) { LocalDate.of(2026, 8, 20) }.readList(desk, "3 June: Riverside A v Grange A\n8 Oct Crown v Dolphin\n15 Oct Grange A v Grange A")!!
        assertEquals("date", read.rows[0].doubt, "3 June is in no year of this season")
        assertNull(read.rows[0].scheduledAt)
        assertEquals("teams", read.rows[1].doubt, "the Crown is not in this season")
        assertEquals("teams", read.rows[2].doubt, "a team does not play itself")
        // No line states a time, so none is invented: the row says so and the person supplies one for them all.
        val timeless = Understanding(reader) { LocalDate.of(2026, 8, 20) }.readList(desk, "8 Oct Riverside A v Dolphin")!!
        assertEquals("time", timeless.rows[0].doubt); assertNull(timeless.rows[0].time)
    }

    @Test
    fun `too long a list is refused, and a model that answers nothing is no reading`() {
        val reader = Reader()
        val long = (1..201).joinToString("\n") { "8 Oct Riverside A v Dolphin" }
        assertEquals("A list is at most 200 lines. Paste it in parts.", runCatching { Understanding(reader) { LocalDate.of(2026, 8, 20) }.readList(desk, long) }.exceptionOrNull()?.message)
        val silent = object : SystemOne { override fun answers(state: String, questions: String): Map<String, Any?>? = null }
        assertNull(Understanding(silent) { LocalDate.of(2026, 8, 20) }.readList(desk, "8 Oct Riverside A v Dolphin"))
    }
}
