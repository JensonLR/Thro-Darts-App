package thro.api

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * A pasted results sheet, read with no model (PD-159).
 *
 * **The headline number is rows wrong while ready** — a row THRØ pre-ticked and got wrong is the one a secretary
 * confirms without looking, and the only failure here that can put a false result in a league table. A row that
 * comes back in doubt costs a tap; a row wrong and ready costs the table.
 *
 * Second, reported and not gated: how many of the 45 are ready *and* right. If that number is low the secretary is
 * still doing the work by hand and the feature is not worth having, however safe it is.
 *
 * This test spends nothing: no key, no network.
 */
class ResultsSheetTest {

    private val desk = ProductionDesk.desk

    @Test
    fun `the sheet is read, and what it gets wrong while looking ready is counted`() {
        val paste = ResultsSheetLines.lines.joinToString("\n") { it.text }
        val read = ResultsSheet.read(desk, paste)
        val byText = read.rows.associateBy { it.text }

        var wrongWhileReady = 0; var readyAndRight = 0; var inDoubt = 0; var notSeen = 0
        val wrong = mutableListOf<String>()
        val doubted = mutableListOf<String>()

        for (line in ResultsSheetLines.results) {
            val row = byText[line.text]
            if (row == null) { notSeen++; wrong += "NOT SEEN AT ALL: ${line.text}"; continue }
            val kindOk = row.kind?.name == when (line.kind) { "played" -> "PLAYED"; "awarded" -> "AWARDED"; else -> "NOT_PLAYED" }
            val pairOk = row.fixture?.let { setOf(it.home, it.away) == setOf(line.pair!!.first, line.pair.second) } ?: false
            // The legs the line wrote, mapped onto the fixture's own home and away — no position-finding here: the
            // label says which team each number belongs to, so this checks the code rather than agreeing with it.
            val legsOk = when {
                line.legs == null -> row.legsHome == null && row.legsAway == null
                row.fixture == null -> false
                else -> {
                    val byTeam = mapOf(line.pair!!.first to line.legs.first, line.pair.second to line.legs.second)
                    row.legsHome == byTeam[row.fixture!!.home] && row.legsAway == byTeam[row.fixture!!.away]
                }
            }
            val awardOk = line.awardTo == null || row.awardTo?.name == line.awardTo
            val right = kindOk && pairOk && legsOk && awardOk
            when {
                row.ready && right -> readyAndRight++
                row.ready && !right -> { wrongWhileReady++; wrong += "READY BUT WRONG: ${line.text} → kind=${row.kind} pair=${row.fixture?.let { "${it.home} v ${it.away}" }} legs=${row.legsHome}-${row.legsAway} award=${row.awardTo?.name}" }
                else -> { inDoubt++; doubted += "${line.text} → doubt: ${row.doubt}" }
            }
        }

        // The 10 lines that are not results must not become rows at all.
        val furnitureAsRows = ResultsSheetLines.notResults.filter { byText.containsKey(it.text) && it.text.isNotBlank() }

        val out = StringBuilder()
        out.appendLine("# A pasted results sheet, read with no model (PD-159)"); out.appendLine()
        out.appendLine("Desk: ${ProductionDesk.teams.size} teams, ${ProductionDesk.fixtures.size} fixtures, every pair meeting twice.")
        out.appendLine("Sheet: ${ResultsSheetLines.lines.size} lines — ${ResultsSheetLines.results.size} results, ${ResultsSheetLines.notResults.size} not, across nine dated weeks. Labelled before the first run.")
        out.appendLine()
        out.appendLine("| | Count |")
        out.appendLine("|---|---|")
        out.appendLine("| **Wrong while ready** (the one that reaches a table) | **$wrongWhileReady of ${ResultsSheetLines.results.size}** |")
        out.appendLine("| Ready and right | $readyAndRight of ${ResultsSheetLines.results.size} |")
        out.appendLine("| In doubt, costing a tap | $inDoubt |")
        out.appendLine("| Not seen at all | $notSeen |")
        out.appendLine("| Sheet furniture wrongly made into a row | ${furnitureAsRows.size} of ${ResultsSheetLines.notResults.size} |")
        out.appendLine()
        if (wrong.isNotEmpty()) { out.appendLine("## Wrong"); out.appendLine(); wrong.forEach { out.appendLine("- $it") }; out.appendLine() }
        if (doubted.isNotEmpty()) { out.appendLine("## In doubt — what a question would have to buy"); out.appendLine(); doubted.forEach { out.appendLine("- $it") }; out.appendLine() }
        if (furnitureAsRows.isNotEmpty()) { out.appendLine("## Furniture read as a result"); out.appendLine(); furnitureAsRows.forEach { out.appendLine("- ${it.text}") } }
        File("build").mkdirs(); File("build/results-sheet-floor.md").writeText(out.toString())
        println(out)

        assertEquals(0, wrongWhileReady, "a row THRØ pre-ticked and got wrong is the one a secretary confirms without looking")
        assertEquals(0, furnitureAsRows.size, "a heading, a table row or a rubric is never a result")
        assertTrue(readyAndRight >= 40, "reported, not gated: below this the secretary is still doing it by hand (got $readyAndRight)")
    }

    @Test
    fun `nothing is silently dropped - a line that is not read is said back`() {
        val read = ResultsSheet.read(desk, ResultsSheetLines.lines.joinToString("\n") { it.text })
        assertEquals(ResultsSheetLines.lines.size, read.rows.size + read.skipped.size,
                     "every line of the paste is either a row or a visible skip")
    }

    @Test
    fun `a pair that meets twice is left in doubt rather than assigned to a coin's toss`() {
        val read = ResultsSheet.read(desk, "Grange A 5 Dolphin 3")
        val row = read.rows.single()
        assertEquals("which week", row.doubt, "two meetings, no date: the row says which part it cannot settle")
        assertTrue(!row.ready, "and it is not offered for a tap")
    }

    @Test
    fun `a paste too long is refused in words rather than read slowly`() {
        val huge = "Grange A 5 Dolphin 3\n".repeat(2000)
        val refused = runCatching { ResultsSheet.read(desk, huge) }.exceptionOrNull()
        assertTrue(refused is IllegalArgumentException, "a 20,000-character ceiling, said as 'paste it in parts'")
    }
}
