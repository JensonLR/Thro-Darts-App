package thro.api

/**
 * A week's results sheet, read into rows an organiser ticks (PD-159).
 *
 * A league secretary has twenty fixtures and twenty forms on a Sunday night. `Understanding.readList` already reads
 * a pasted *fixture* list line by line; the same sheet with scores on it was not read at all.
 *
 * **This reads it with no model.** PD-154's rule is to write the `for` loop first and publish its number, and
 * PD-158 showed why: on the fixture desk the floor did the whole job the two proposed questions were for. The parts
 * here are the same shape — a scoreline is a regex, a team is [TeamNames], an outcome is a short phrase list, and a
 * fixture is (pair + the date the sheet's own heading carries down). What this cannot do is written down in
 * [Row.doubt] rather than guessed at, and that residue is the only thing a question could be bought for.
 *
 * **Nothing here writes anything.** It returns rows. A person ticks them and presses Record, and that calls the
 * ordinary routes with the ordinary permissions.
 */
public object ResultsSheet {

    /** How a match ended, as a sheet says it. */
    public enum class Kind { PLAYED, AWARDED, NOT_PLAYED }

    /**
     * One line, read. [ready] is the only thing the screen may pre-tick, and it is deliberately hard to earn:
     * every part present, a fixture resolved to exactly one, and nothing in [doubt].
     */
    public data class Row(
        val number: Int,
        val text: String,
        val kind: Kind? = null,
        val fixture: Understanding.Fixture? = null,
        val legsHome: Int? = null,
        val legsAway: Int? = null,
        val awardTo: Understanding.Team? = null,
        val doubt: String? = null,
        val ready: Boolean = false,
    )

    /** A line that is not a result and is not silently dropped: the sheet's furniture, said back so it is visible. */
    public data class Skipped(val number: Int, val text: String, val why: String)

    public data class Read(val rows: List<Row>, val skipped: List<Skipped>)

    /** The most a sheet may carry in one paste. Beyond it the answer is "paste it in parts", not a slower read. */
    public const val MAX_LINES: Int = 200
    public const val MAX_CHARACTERS: Int = 20_000

    private val WALKOVER = listOf("w/o", "wo ", "walkover", "walk over", "conceded", "concede", "awarded",
                                  "could not raise", "couldn't raise", "cant raise", "can't raise", "forfeit", "scratched")
    private val NOT_PLAYED = listOf("postponed", "p/p", "pp ", "off,", " off", "void", "cancelled", "canceled",
                                    "abandoned", "rearranged", "not played")
    /** A row with dashes or blanks where the two numbers would be: played nothing, said nothing. */
    private val EMPTY_SCORE = Regex("""[-–—]\s*[-–—]\s*$""")

    private val MONTHS = listOf("january", "february", "march", "april", "may", "june", "july", "august",
                                "september", "october", "november", "december")
    /** "15 October 2026", "15th October", "Thursday 15 October 2026". */
    private val DAY_MONTH = Regex("""\b(\d{1,2})(?:st|nd|rd|th)?\s+(""" + MONTHS.joinToString("|") + """)\b(?:\s+(\d{4}))?""",
                                  RegexOption.IGNORE_CASE)
    /** "15/10/2026", "15-10-26". */
    private val SLASHED = Regex("""\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b""")

    /**
     * The date a line carries, where it carries one (PD-159).
     *
     * **This is what makes the sheet usable rather than merely safe.** Every pair in a double round-robin meets
     * twice, so a line saying "Grange A 5 Dolphin 3" names two fixtures and chooses neither. Measured with no
     * heading, the floor got **0 of 45 wrong while ready — and 0 ready at all**, because every single row was
     * honestly in doubt. A sheet's own heading ("Results for Thursday 15 October 2026") settles every row beneath
     * it, exactly as `Understanding.readList` already carries a heading down a fixture list.
     */
    internal fun dateOn(line: String): java.time.LocalDate? {
        DAY_MONTH.find(line)?.let { m ->
            val day = m.groupValues[1].toIntOrNull() ?: return@let
            val month = MONTHS.indexOf(m.groupValues[2].lowercase()) + 1
            val year = m.groupValues[3].toIntOrNull()
            if (day in 1..31 && month in 1..12 && year != null) return java.time.LocalDate.of(year, month, day)
            if (day in 1..31 && month in 1..12) return java.time.LocalDate.of(java.time.LocalDate.now().year, month, day)
        }
        SLASHED.find(line)?.let { m ->
            val day = m.groupValues[1].toInt(); val month = m.groupValues[2].toInt()
            var year = m.groupValues[3].toInt(); if (year < 100) year += 2000
            if (day in 1..31 && month in 1..12) return java.time.LocalDate.of(year, month, day)
        }
        return null
    }

    /**
     * Reads a paste against a season's desk. [headingDate] is not guessed: where a line carries no date and no
     * heading has been seen, a pair that meets twice is left in doubt rather than assigned to a coin's toss.
     */
    public fun read(desk: Understanding.Desk, paste: String, headingDate: java.time.LocalDate? = null): Read {
        require(paste.length <= MAX_CHARACTERS) { "Paste it in parts." }
        val rows = mutableListOf<Row>()
        val skipped = mutableListOf<Skipped>()

        // The date in force: the last one a heading stated. A heading is a line with a date and no fixture on it.
        var inForce: java.time.LocalDate? = headingDate

        for ((index, raw) in paste.lines().take(MAX_LINES).withIndex()) {
            val number = index + 1
            val line = raw.trim()
            if (line.isEmpty()) { skipped += Skipped(number, raw, "an empty line"); continue }

            // Both sides named is the gate, and it is the same one PD-158 measured at 20 of 20 against sentences
            // about fixtures a season has not got.
            val candidates = Understanding.fixturesNamed(desk, line)
            if (candidates.isEmpty()) {
                // Before giving up on it: a line with a date and no fixture is a heading, and it governs what follows.
                dateOn(line)?.let { inForce = it }
                skipped += Skipped(number, line, if (dateOn(line) != null) "a heading: every result under it is dated ${dateOn(line)}"
                                                 else "THRØ could not see two of this season's teams in this line")
                continue
            }

            val lower = " ${line.lowercase()} "
            val kind = when {
                NOT_PLAYED.any { lower.contains(it) } -> Kind.NOT_PLAYED
                WALKOVER.any { lower.contains(it) } -> Kind.AWARDED
                EMPTY_SCORE.containsMatchIn(line) -> Kind.NOT_PLAYED
                else -> Kind.PLAYED
            }

            // Which of the pair's meetings. One candidate is the answer; two is the case a date settles — the
            // line's own, or the one the sheet's heading put in force. Where neither exists the row stays in
            // doubt: a coin's toss between two legs is the one error that reaches a league table unnoticed.
            val dated = dateOn(line) ?: inForce
            val narrowed = if (candidates.size == 1) candidates else dated?.let { d ->
                candidates.filter { it.at.atZone(Understanding.ZONE).toLocalDate() == d }
            } ?: candidates
            val fixture = narrowed.singleOrNull()
            var doubt: String? = if (fixture == null) "which week" else null

            var legsHome: Int? = null; var legsAway: Int? = null; var awardTo: Understanding.Team? = null
            when (kind) {
                Kind.PLAYED -> {
                    val written = Understanding.scorelines(line).firstOrNull()
                    val m = written?.let { Understanding.SCORE_PUBLIC.find(it) }
                    if (m == null) { if (doubt == null) doubt = "the score" }
                    else {
                        val a = m.groupValues[1].toInt(); val b = m.groupValues[2].toInt()
                        // The first number belongs to the team named first in the LINE, which on a sheet is nearly
                        // always the home side — but "nearly always" is not a rule, so the row is resolved against
                        // which of the two teams the line names first, not against the fixture's own home.
                        val f = fixture
                        if (f != null) {
                            val firstNamed = firstNamed(line, f)
                            if (firstNamed == null) { doubt = "which side" }
                            else if (firstNamed == f.home) { legsHome = a; legsAway = b }
                            else { legsHome = b; legsAway = a }
                        }
                    }
                }
                Kind.AWARDED -> {
                    awardTo = awardedTo(line, desk, candidates)
                    if (awardTo == null && doubt == null) doubt = "who it was awarded to"
                }
                Kind.NOT_PLAYED -> Unit
            }
            if (fixture?.decided == true && doubt == null) doubt = "already recorded"

            rows += Row(number, line, kind, fixture, legsHome, legsAway, awardTo, doubt,
                        ready = doubt == null && fixture != null &&
                            (kind != Kind.PLAYED || (legsHome != null && legsAway != null)) &&
                            (kind != Kind.AWARDED || awardTo != null))
        }
        return Read(rows, skipped)
    }

    /**
     * Which of a fixture's two teams this line names first — the order the numbers belong to.
     *
     * **The derby is why the side letter is tried before the stem.** "riverside a 4 riverside b 4" is Riverside A
     * against Riverside B, and both stems are the word `riverside`, found at the same place. Looking for the folded
     * name *with* its letter — "riverside a", "riverside b" — separates them; the stem alone never can, and the
     * honest answer without this is the doubt `which side`, which is where this row sat when it was measured.
     */
    private fun firstNamed(line: String, f: Understanding.Fixture): String? {
        val flat = " " + TeamNames.fold(line) + " "
        fun at(name: String): Int {
            val (stem, letter) = TeamNames.stem(name)
            // The name and its side letter together, which is the only thing that tells two sides of a club apart.
            if (letter != null) {
                val withLetter = flat.indexOf(" $stem $letter ")
                if (withLetter >= 0) return withLetter
            }
            val whole = flat.indexOf(" $stem ")
            if (whole >= 0) return whole
            val longest = stem.split(" ").maxByOrNull { it.length }
            val word = longest?.let { flat.indexOf(" $it ") } ?: -1
            if (word >= 0) return word
            return flat.replace(" ", "").indexOf(stem.replace(" ", ""))
        }
        val h = at(f.home); val a = at(f.away)
        if (h < 0 || a < 0 || h == a) return null
        return if (h < a) f.home else f.away
    }

    /**
     * The team a walkover goes to: **the one the line names as receiving it, never the one at fault.** Where the
     * line names the team at fault in a bracket — "Crown walkover (Sun Inn could not raise a side)" — the receiver
     * is the other one, and where it says "X conceded to Y" the receiver is Y.
     */
    private fun awardedTo(line: String, desk: Understanding.Desk, candidates: List<Understanding.Fixture>): Understanding.Team? {
        val f = candidates.firstOrNull() ?: return null
        val both = listOfNotNull(desk.teams.firstOrNull { it.name == f.home }, desk.teams.firstOrNull { it.name == f.away })
        if (both.size != 2) return null
        val lower = line.lowercase()

        // "X conceded to Y", "X gave it to Y": the receiver follows the verb.
        Regex("""(conceded|forfeited|scratched)\s+to\s+(.+)$""").find(lower)?.let { m ->
            return both.firstOrNull { TeamNames.mentions(m.groupValues[2], it.name) }
        }
        // "X awarded the points against Y": the receiver is before the verb.
        Regex("""^(.+?)\s+(awarded|given)\b""").find(lower)?.let { m ->
            return both.firstOrNull { TeamNames.mentions(m.groupValues[1], it.name) }
        }
        // "X w/o Y", "X walkover (Y could not raise a side)", "X W/O v Y": the receiver is named first.
        val mark = listOf("w/o", "walkover", "walk over").mapNotNull { k -> lower.indexOf(k).takeIf { it >= 0 } }.minOrNull()
        if (mark != null) {
            val before = line.take(mark)
            return both.firstOrNull { TeamNames.mentions(before, it.name) }
        }
        // "Y could not raise a side" with no marker: the receiver is the other one.
        val atFault = both.firstOrNull { t ->
            Regex("""(could ?n[o']?t raise|cannot raise|can't raise|did not turn up|didn't turn up)""").find(lower)?.let { m ->
                TeamNames.mentions(line.take(m.range.first), t.name)
            } ?: false
        }
        return atFault?.let { f2 -> both.first { it != f2 } }
    }
}
