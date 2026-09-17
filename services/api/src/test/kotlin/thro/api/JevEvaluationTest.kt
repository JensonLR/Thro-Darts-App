package thro.api

import java.io.File
import java.net.URI
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.util.UUID
import kotlin.test.Test

/**
 * What THRØ gets from the System One model, measured (PD-123).
 *
 * Every other test here holds THRØ's *code* with a stand-in for the model. This one holds the model: the sentences a
 * league secretary actually types and a fixture list as a league actually publishes it — abbreviations, misspellings,
 * scores written three ways, pub talk — read by the real `jev-latest` through the same `Understanding` the desk uses,
 * and scored against what a person would have meant. It prints a scorecard and writes it to
 * `build/jev-scorecard.md`: how often the act, the fixture and the whole card are right, how often THRØ said it was
 * unsure when it was wrong (the number that matters for a card a person confirms), and how long each reading took.
 *
 * It runs only when a key is in the environment, because it spends the founder's tokens and because CI has no key:
 *
 *     TYPESAFE_API_KEY=… gradle -p services/api test --tests 'thro.api.JevEvaluationTest' --rerun
 *
 * `THRO_TYPESAFE_ENDPOINT` points it at `tools/fake_systemone.py` instead, which is how the harness itself is checked
 * — and the stand-in's score is the floor a word-matcher sets, for the model to be compared against.
 */
class JevEvaluationTest {

    private val today = LocalDate.of(2026, 10, 9)   // a Friday
    private fun team(name: String) = Understanding.Team(UUID.nameUUIDFromBytes(name.toByteArray()), name)
    private val teams = listOf("Riverside A", "Riverside B", "Grange A", "Dolphin", "Bell B", "Crown", "Sun Inn", "Station Hotel").map(::team)
    private fun t(name: String) = teams.first { it.name == name }
    private fun fixture(home: String, away: String, at: String, decided: Boolean = false) =
        Understanding.Fixture(UUID.nameUUIDFromBytes("$home$away$at".toByteArray()), home, t(home).teamId, away, t(away).teamId, Instant.parse(at), decided)
    private val fixtures = listOf(
        fixture("Riverside A", "Dolphin", "2026-10-01T18:30:00Z", decided = true), fixture("Crown", "Grange A", "2026-10-01T18:30:00Z", decided = true),
        fixture("Riverside A", "Grange A", "2026-10-08T18:30:00Z"), fixture("Dolphin", "Bell B", "2026-10-08T18:30:00Z"),
        fixture("Crown", "Sun Inn", "2026-10-08T18:30:00Z"), fixture("Station Hotel", "Riverside B", "2026-10-08T18:30:00Z"),
        fixture("Grange A", "Dolphin", "2026-10-15T18:30:00Z"), fixture("Bell B", "Crown", "2026-10-15T18:30:00Z"),
        fixture("Sun Inn", "Station Hotel", "2026-10-15T18:30:00Z"), fixture("Riverside B", "Riverside A", "2026-10-15T18:30:00Z"),
    )
    private val desk = Understanding.Desk(fixtures, teams, LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))

    /** What a person meant. Only the parts named are scored; [fixture] is "Home v Away". */
    private data class Meant(val text: String, val act: String, val fixture: String? = null, val legs: Pair<Int, Int>? = null, val awardTo: String? = null,
                             val on: LocalDate? = null, val time: LocalTime? = null, val teams: Pair<String, String>? = null)

    private val sentences = listOf(
        Meant("Riverside A beat Grange A 5-3 last night", "result", "Riverside A v Grange A", 5 to 3),
        Meant("Grange lost 3-5 at Riverside", "result", "Riverside A v Grange A", 5 to 3),
        Meant("Dolphin 6 Bell B 2", "result", "Dolphin v Bell B", 6 to 2),
        Meant("Bell B got hammered 7-1 by Dolphin", "result", "Dolphin v Bell B", 7 to 1),
        Meant("the Crown and the Sun drew 4 each, 4-4", "result", "Crown v Sun Inn", 4 to 4),
        Meant("station 5 riverside b 1", "result", "Station Hotel v Riverside B", 5 to 1),
        Meant("Riverside B won away at the Station, 4-2", "result", "Station Hotel v Riverside B", 2 to 4),
        Meant("Walkover to Station Hotel, Riverside B couldn't raise a team", "award", "Station Hotel v Riverside B", awardTo = "Station Hotel"),
        Meant("Sun Inn didn't turn up at the Crown so give it to the Crown", "award", "Crown v Sun Inn", awardTo = "Crown"),
        Meant("Grange forfeit next week's game against Dolphin, they're all at a wedding", "award", "Grange A v Dolphin", awardTo = "Dolphin"),
        Meant("Scrub the Riverside A v Dolphin result, the wrong sheet was handed in", "void", "Riverside A v Dolphin"),
        Meant("the Crown Grange result from last week needs annulling, ineligible player", "void", "Crown v Grange A"),
        Meant("Move Grange v Dolphin to Friday 16th at 8", "move", "Grange A v Dolphin", on = LocalDate.of(2026, 10, 16), time = LocalTime.of(20, 0)),
        Meant("Bell B v Crown is off, the pub's flooded. Rearranged for 29 October", "move", "Bell B v Crown", on = LocalDate.of(2026, 10, 29), time = LocalTime.of(19, 30)),
        Meant("can we push the Sun Inn Station game back to the 22nd", "move", "Sun Inn v Station Hotel", on = LocalDate.of(2026, 10, 22), time = LocalTime.of(19, 30)),
        Meant("Riverside derby postponed until Tuesday 20 October, 7.45pm", "move", "Riverside B v Riverside A", on = LocalDate.of(2026, 10, 20), time = LocalTime.of(19, 45)),
        Meant("Add Sun Inn v Dolphin on 22 October 7.30pm", "schedule", on = LocalDate.of(2026, 10, 22), time = LocalTime.of(19, 30), teams = "Sun Inn" to "Dolphin"),
        Meant("new fixture: riverside b at home to crown, 5 november, 8pm", "schedule", on = LocalDate.of(2026, 11, 5), time = LocalTime.of(20, 0), teams = "Riverside B" to "Crown"),
        Meant("Put Bell B away to Grange on the 12th of November at half seven — 7.30", "schedule", on = LocalDate.of(2026, 11, 12), time = LocalTime.of(19, 30), teams = "Grange A" to "Bell B"),
        Meant("What time do the Crown play next week?", "none"),
        Meant("thanks Lee, see you Thursday", "none"),
        Meant("who's top of the table", "none"),
    )

    private val pasted = """
        TEESSIDE THURSDAY LEAGUE 2026/27 — DIVISION ONE
        all matches 7.30pm unless shown

        Thursday 22nd October
        R'side A v Grange
        Dolphins v Bell B
        The Crown v Sun
        Stn Hotel v Riverside B  8pm

        Thurs 29 Oct
        Grnage A v Riverside A
        Bell v Dolphin
        Sun Inn v Crown
        Riverside B v Station Htl
        (Week 5 — cup week, no league fixtures)

        5 Nov: Crown v Riverside A
        5 Nov: Station Hotel v Dolphin - 8.15
    """.trimIndent()
    private val listMeant = listOf(
        Triple("Riverside A", "Grange A", LocalDate.of(2026, 10, 22)), Triple("Dolphin", "Bell B", LocalDate.of(2026, 10, 22)),
        Triple("Crown", "Sun Inn", LocalDate.of(2026, 10, 22)), Triple("Station Hotel", "Riverside B", LocalDate.of(2026, 10, 22)),
        Triple("Grange A", "Riverside A", LocalDate.of(2026, 10, 29)), Triple("Bell B", "Dolphin", LocalDate.of(2026, 10, 29)),
        Triple("Sun Inn", "Crown", LocalDate.of(2026, 10, 29)), Triple("Riverside B", "Station Hotel", LocalDate.of(2026, 10, 29)),
        Triple("Crown", "Riverside A", LocalDate.of(2026, 11, 5)), Triple("Station Hotel", "Dolphin", LocalDate.of(2026, 11, 5)),
    )

    /** Times each request, whatever answers it. */
    private class Timed(val inner: SystemOne) : SystemOne {
        val millis: MutableList<Long> = java.util.Collections.synchronizedList(mutableListOf())
        override fun answers(state: String, questions: String): Map<String, Any?>? {
            val start = System.nanoTime()
            return inner.answers(state, questions).also { millis += (System.nanoTime() - start) / 1_000_000 }
        }
    }

    @Test
    fun `the model reads a secretary's sentences and a league's list, and is scored`() {
        val key = System.getenv("TYPESAFE_API_KEY")?.takeIf { it.isNotBlank() } ?: System.getenv("THRO_TYPESAFE_API_KEY")?.takeIf { it.isNotBlank() }
        if (key == null) { println("no TypeSafe key in the environment — the model is not evaluated here"); return }
        val endpoint = System.getenv("THRO_TYPESAFE_ENDPOINT")?.takeIf { it.isNotBlank() }
        val reader = if (endpoint != null) TypeSafeReader(key, endpoint = URI(endpoint), timeout = Duration.ofSeconds(10)) else TypeSafeReader(key, timeout = Duration.ofSeconds(10))
        val model = Timed(reader)
        val u = Understanding(model) { today }
        val out = StringBuilder()
        fun say(line: String) { println(line); out.appendLine(line) }

        say("# What THRØ gets from the System One model"); say("")
        say("Model: ${if (endpoint != null) "the stand-in at $endpoint (a word-matcher; the floor)" else "jev-latest"} · ${Instant.now()} · desk of ${teams.size} teams, ${fixtures.size} fixtures, today ${today}."); say("")
        say("## Sentences on the desk"); say("")
        say("| | Sentence | Meant | Read | Confidence |"); say("|---|---|---|---|---|")
        var acts = 0; var fixturesRight = 0; var fixturesAsked = 0; var whole = 0; var unanswered = 0
        var wrongAndSure = 0; var wrongAndUnsure = 0
        for (m in sentences) {
            val r = u.understand(desk, m.text)
            if (r == null) { unanswered++; say("| ✗ | ${m.text} | ${m.act} | *no answer* | |"); continue }
            val actOk = r.act == m.act
            val fixtureOk = m.fixture == null || r.fixture?.let { "${it.home} v ${it.away}" } == m.fixture
            val legsOk = m.legs == null || r.result?.let { it.legsHome to it.legsAway } == m.legs
            val awardOk = m.awardTo == null || r.award?.toName == m.awardTo
            val date = r.move?.on ?: r.schedule?.on; val time = r.move?.time ?: r.schedule?.time
            val dateOk = m.on == null || date == m.on
            val timeOk = m.time == null || time == m.time
            val teamsOk = m.teams == null || r.schedule?.let { it.home to it.away } == m.teams
            val all = actOk && fixtureOk && legsOk && awardOk && dateOk && timeOk && teamsOk
            if (actOk) acts++
            if (m.fixture != null) { fixturesAsked++; if (fixtureOk && actOk) fixturesRight++ }
            if (all) whole++ else if (r.doubt == null && r.confidence >= 0.75) wrongAndSure++ else wrongAndUnsure++
            say("| ${if (all) "✓" else "✗"} | ${m.text} | ${m.act}${m.fixture?.let { " · $it" } ?: ""} | ${r.say.replace("|", "/")}${r.doubt?.let { " *(check the $it)*" } ?: ""} | ${"%.2f".format(r.confidence)} |")
        }
        val n = sentences.size
        say(""); say("- The act right: **$acts of $n**. The fixture right: **$fixturesRight of $fixturesAsked**. The whole card right, nothing to change: **$whole of $n**.")
        say("- Of the ${n - whole - unanswered} cards that needed a change, THRØ had said it was unsure on **$wrongAndUnsure** and had been sure on **$wrongAndSure** — the second is the number to drive to nothing.")
        if (unanswered > 0) say("- No answer at all: $unanswered.")

        say(""); say("## A pasted fixture list"); say("")
        val startList = model.millis.size
        val read = u.readList(desk, pasted)
        if (read == null) say("*no answer*") else {
            say("| | The league's line | Read | Doubt |"); say("|---|---|---|---|")
            var rowsRight = 0
            for ((i, meant) in listMeant.withIndex()) {
                val row = read.rows.getOrNull(i)
                val ok = row != null && row.home == meant.first && row.away == meant.second && row.on == meant.third && row.doubt == null
                if (ok) rowsRight++
                say("| ${if (ok) "✓" else "✗"} | ${row?.text ?: "*missing*"} | ${row?.let { "${it.home} v ${it.away}, ${it.on} ${it.time}" } ?: ""} | ${row?.doubt ?: ""} |")
            }
            say(""); say("- Rows right, nothing to change: **$rowsRight of ${listMeant.size}** (${read.rows.size} rows read, ${read.skipped.size} lines left out: ${read.skipped.joinToString(" · ") { "“${it.text}” — ${it.why}" }}).")
        }

        val ms = model.millis.toList()
        if (ms.isNotEmpty()) {
            val sorted = ms.sorted()
            say(""); say("## Speed"); say("")
            say("- ${ms.size} requests. Median **${sorted[sorted.size / 2]} ms**, 95th percentile **${sorted[(sorted.size * 95 / 100).coerceAtMost(sorted.size - 1)]} ms**, slowest ${sorted.last()} ms.")
            say("- A sentence is one request (${sentences.size} of them); the ${ms.size - startList} lines of the list went six at a time.")
        }
        File("build").mkdirs(); File("build/jev-scorecard.md").writeText(out.toString())
        println("written to services/api/build/jev-scorecard.md")
    }
}
