package thro.api

/**
 * A results sheet as a league secretary pastes it (PD-159): several weeks of a division, caught up at once.
 *
 * **Labelled before anything was run against it**, in the register real sheets are written in — a heading carrying
 * the week's date, division names, a rubric, a table row that is not a result, scores written five ways, walkovers
 * in prose, postponements, and a blank where a score would be.
 *
 * The pairs under each heading are the ones that week's round actually plays, because that is what a sheet is. The
 * *wording* is hand-written and deliberately inconsistent; that is what is being read.
 *
 * 55 lines: 45 report a match, 10 do not. The number that matters is not how many are read — it is how many are
 * read **wrongly while looking ready**, because that is the one a secretary ticks without noticing.
 */
internal object ResultsSheetLines {

    /**
     * [pair] is the two teams **in the order the line names them**, or null when the line is not a result at all,
     * and [legs] is the scoreline in that same order. Written this way on purpose: a test that had to work out for
     * itself which team a line named first would be re-implementing the thing it is checking, and the first version
     * of this file did exactly that and reported a correct row as wrong.
     */
    data class Line(val text: String, val pair: Pair<String, String>? = null, val kind: String = "none",
                    val legs: Pair<Int, Int>? = null, val awardTo: String? = null)

    val lines: List<Line> = listOf(
        Line("STOCKTON & DISTRICT DARTS LEAGUE — Division One"),
        Line("All matches 7.30pm unless stated"),
        Line(""),

        Line("Week 1 — Thursday 3 September 2026"),
        Line("O'Grady's 5 Grange B 3", "O'Grady's" to "Grange B", "played", 5 to 3),
        Line("Riverside A 4 Thornaby F.C 4", "Riverside A" to "Thornaby F.C", "played", 4 to 4),
        Line("Station Hotel 6 - 2 Riverside B", "Station Hotel" to "Riverside B", "played", 6 to 2),
        Line("The Blue Bell 7-1 Sun Inn", "The Blue Bell" to "Sun Inn", "played", 7 to 1),
        Line("Crown v Dolphin  3-5", "Crown" to "Dolphin", "played", 3 to 5),

        Line("Week 2 — Thursday 10 September 2026"),
        Line("O'Grady's beat Grange A 6-2", "O'Grady's" to "Grange A", "played", 6 to 2),
        Line("Station Hotel 4 Grange B 4", "Station Hotel" to "Grange B", "played", 4 to 4),
        Line("Riverside A lost 3-5 to Sun Inn", "Riverside A" to "Sun Inn", "played", 3 to 5),
        Line("Crown 8 Riverside B 0", "Crown" to "Riverside B", "played", 8 to 0),
        Line("blue bell 2 dolphin 6", "The Blue Bell" to "Dolphin", "played", 2 to 6),

        Line("Week 3 — Thursday 17 September 2026"),
        Line("Grange A 5 Thornaby 3", "Grange A" to "Thornaby F.C", "played", 5 to 3),
        Line("Station Hotel 1 O'Gradys 7", "Station Hotel" to "O'Grady's", "played", 1 to 7),
        Line("Crown w/o Grange B", "Crown" to "Grange B", "awarded", awardTo = "Crown"),
        Line("Riverside A 4-4 Dolphin", "Riverside A" to "Dolphin", "played", 4 to 4),
        Line("The Blue Bell v Riverside B — postponed", "The Blue Bell" to "Riverside B", "not_played"),

        Line("P  W  D  L  Pts"),
        Line("Crown   3  3  0  0   9"),
        Line(""),

        Line("Week 4 — Thursday 24 September 2026"),
        Line("station 5 grange a 1", "Station Hotel" to "Grange A", "played", 5 to 1),
        Line("Thornaby F.C conceded to Sun Inn", "Thornaby F.C" to "Sun Inn", "awarded", awardTo = "Sun Inn"),
        Line("Crown 6 O'Grady's 2", "Crown" to "O'Grady's", "played", 6 to 2),
        Line("The Blue Bell 3–5 Grange B", "The Blue Bell" to "Grange B", "played", 3 to 5),
        Line("riverside a 4 riverside b 4", "Riverside A" to "Riverside B", "played", 4 to 4),

        Line("Week 5 — Thursday 1 October 2026"),
        Line("Grange A 7 Sun Inn 1", "Grange A" to "Sun Inn", "played", 7 to 1),
        Line("Crown v Station Hotel  P/P", "Crown" to "Station Hotel", "not_played"),
        Line("Thornaby F.C 2 Dolphin 6", "Thornaby F.C" to "Dolphin", "played", 2 to 6),
        Line("The Blue Bell awarded the points against O'Grady's", "The Blue Bell" to "O'Grady's", "awarded", awardTo = "The Blue Bell"),
        Line("Riverside A 5 Grange B 3", "Riverside A" to "Grange B", "played", 5 to 3),

        Line("Week 6 — Thursday 8 October 2026"),
        Line("Crown 4 Grange A 4", "Crown" to "Grange A", "played", 4 to 4),
        Line("Sun Inn 6-2 Dolphin", "Sun Inn" to "Dolphin", "played", 6 to 2),
        Line("The Blue Bell 3 Station Hotel 5", "The Blue Bell" to "Station Hotel", "played", 3 to 5),
        Line("Thornaby v Riverside B  0-8", "Thornaby F.C" to "Riverside B", "played", 0 to 8),
        Line("Riverside A 5 O'Gradys 3", "Riverside A" to "O'Grady's", "played", 5 to 3),

        Line("Week 7 — Thursday 15 October 2026"),
        Line("Grange A 5 Dolphin 3", "Grange A" to "Dolphin", "played", 5 to 3),
        Line("The Blue Bell 2 Crown 6", "The Blue Bell" to "Crown", "played", 2 to 6),
        Line("Sun Inn W/O v Riverside B", "Sun Inn" to "Riverside B", "awarded", awardTo = "Sun Inn"),
        Line("Riverside A v Station Hotel    -    -", "Riverside A" to "Station Hotel", "not_played"),
        Line("thornaby 4 grange b 4", "Thornaby F.C" to "Grange B", "played", 4 to 4),

        Line("Week 8 — Thursday 22 October 2026"),
        Line("The Blue Bell 6 Grange A 2", "The Blue Bell" to "Grange A", "played", 6 to 2),
        Line("Dolphin 5 Riverside B 3", "Dolphin" to "Riverside B", "played", 5 to 3),
        Line("Riverside A drew 4-4 with Crown", "Riverside A" to "Crown", "played", 4 to 4),
        Line("Sun Inn 7 Grange B 1", "Sun Inn" to "Grange B", "played", 7 to 1),
        Line("Thornaby F.C v O'Grady's — off, pub closed", "Thornaby F.C" to "O'Grady's", "not_played"),

        Line("Week 9 — Thursday 29 October 2026"),
        Line("Grange A 6 - 2 Riverside B", "Grange A" to "Riverside B", "played", 6 to 2),
        Line("Riverside A 3 The Blue Bell 5", "Riverside A" to "The Blue Bell", "played", 3 to 5),
        Line("Dolphin walkover (Grange B could not raise a side)", "Dolphin" to "Grange B", "awarded", awardTo = "Dolphin"),
        Line("sun inn 5 o gradys 3", "Sun Inn" to "O'Grady's", "played", 5 to 3),
        Line("Thornaby F.C 1 Station Hotel 7", "Thornaby F.C" to "Station Hotel", "played", 1 to 7),

        Line("Next week's fixtures overleaf"),
        Line("Any queries to the league secretary"),
    )

    val results: List<Line> get() = lines.filter { it.pair != null }
    val notResults: List<Line> get() = lines.filter { it.pair == null }
}
