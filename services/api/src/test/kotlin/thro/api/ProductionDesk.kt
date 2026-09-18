package thro.api

import java.time.Instant
import java.time.LocalDate
import java.util.UUID

/**
 * The held-out fixture desk at production size (PD-158), shared by the floor test and the model evaluation so both
 * are scored on the same board.
 *
 * `JevEvaluationTest`'s original desk is 8 teams and 10 fixtures, and **no pair in it ever meets twice**. A real
 * division is a double round-robin — Redcar Division 1's eleven teams play 110 fixtures, Stockton Thursday's
 * eighteen play 306 — so the case that can quietly corrupt a league table, a sentence matched to the wrong leg of a
 * fixture a pair plays twice, was never on the board any published number was measured against.
 */
internal object ProductionDesk {

    val today: LocalDate = LocalDate.of(2026, 10, 9)

    /** Eleven teams, named as a real division is — including two sides of one club, which is the hard case. */
    val names: List<String> = listOf(
        "Grange A", "Grange B", "Riverside A", "Riverside B", "The Blue Bell", "Dolphin",
        "Crown", "Sun Inn", "Station Hotel", "Thornaby F.C", "O'Grady's",
    )

    private fun team(name: String) = Understanding.Team(UUID.nameUUIDFromBytes(name.toByteArray()), name)
    val teams: List<Understanding.Team> = names.map(::team)
    private fun t(n: String) = teams.first { it.name == n }

    /**
     * A full double round-robin on a real schedule (the circle method): **five fixtures every Thursday**, eleven
     * rounds to a half, the sides swapped after Christmas. 110 fixtures, 55 pairs, each meeting twice.
     *
     * The weekly round matters as much as the double meeting. A league plays a whole round on one night, so a
     * sheet's heading dates five results at once — and a date that picks out one fixture of a hundred and ten
     * would be a board no secretary has ever pasted into.
     *
     * **Only the opening week is already decided.** Enough that a sheet repeating it is caught as "already
     * recorded"; not so much that the measurement is dominated by rows no secretary would be pasting.
     */
    val fixtures: List<Understanding.Fixture> = buildList {
        val withBye = names + "BYE"
        var order = withBye.indices.toMutableList()
        val rounds = mutableListOf<List<Pair<String, String>>>()
        for (r in 0 until withBye.size - 1) {
            val pairs = mutableListOf<Pair<String, String>>()
            for (i in 0 until withBye.size / 2) {
                val a = withBye[order[i]]; val b = withBye[order[withBye.size - 1 - i]]
                if (a != "BYE" && b != "BYE") pairs += if ((r + i) % 2 == 0) a to b else b to a
            }
            rounds += pairs
            order = (listOf(order[0], order.last()) + order.subList(1, order.size - 1)).toMutableList()
        }
        val first = Instant.parse("2026-09-03T18:30:00Z")
        for (half in 0..1) for ((r, round) in rounds.withIndex()) {
            val week = half * rounds.size + r
            val at = first.plusSeconds(week * 7L * 86_400)
            for ((h, a) in round) {
                val (home, away) = if (half == 0) h to a else a to h
                add(Understanding.Fixture(UUID.nameUUIDFromBytes("$home$away$at".toByteArray()),
                                          home, t(home).teamId, away, t(away).teamId, at, decided = week == 0))
            }
        }
    }

    val desk: Understanding.Desk = Understanding.Desk(fixtures, teams, LocalDate.of(2026, 9, 1), LocalDate.of(2027, 5, 31))

    /**
     * Twenty sentences about a fixture this season has not got, **sealed before any of them was run** and never
     * edited since. The truth for every one is *no fixture*; the number that matters is how many produce one anyway.
     */
    val noSuchFixture: List<String> = listOf(
        "Barwick Arms beat Redcar Rugby 5-3",
        "Middlesbrough Empire 6 Normanby Legion 2",
        "The Ship v The Anchor postponed",
        "Yarm WMC lost 2-5 at Eaglescliffe",
        "Crown beat Crown 5-0",
        "Dolphin drew with Dolphin",
        "Grange A v Grange A called off",
        "the away leg at Hartlepool Catholic Club is off",
        "Sun Inn played a friendly against a pub from Darlington",
        "Station Hotel beat a team from the other league 4-1",
        "Riverside A beat Marske Cricket Club 6-0",
        "thanks all, table looks right now",
        "who do we play next week",
        "can somebody ring the Blue Bell about the darts",
        "I've paid the league fees",
        "is there darts on Boxing Day",
        "Thornaby played really well last night",
        "O'Grady's are struggling this season",
        "put me down as unavailable for the next three weeks",
        "the away end at the Crown is freezing",
    )

    /**
     * Sentences that DO name a fixture the season has. Without these the count above is worthless — a check that
     * rejected everything would score the sealed set perfectly.
     *
     * **These are tuned-on, and the sealed twenty are not.** Two of them ("the Crown and the Sun", "o grady s lost
     * at thornaby") were misses on the first run and the matcher was widened to meet them: a three-letter word may
     * carry a name, and a stem may be matched with its spaces taken out. The sealed set was re-run after that
     * change and still rejects all twenty, which is the only reason the widening was kept.
     */
    val realFixture: List<Pair<String, Set<String>>> = listOf(
        "Riverside A beat Grange A 5-3 last night" to setOf("Riverside A", "Grange A"),
        "Grange lost 3-5 at Riverside" to setOf("Grange A", "Riverside A"),
        "Dolphin 6 Crown 2" to setOf("Dolphin", "Crown"),
        "the Crown and the Sun drew 4 each, 4-4" to setOf("Crown", "Sun Inn"),
        "station 5 riverside b 1" to setOf("Station Hotel", "Riverside B"),
        "Walkover to Station Hotel, Sun Inn couldn't raise a team" to setOf("Station Hotel", "Sun Inn"),
        "Blue Bell v Dolphin is off, the pub's flooded" to setOf("The Blue Bell", "Dolphin"),
        "can we push the Sun Inn Station game back to the 22nd" to setOf("Sun Inn", "Station Hotel"),
        "Thornaby FC beat O'Gradys 6-1" to setOf("Thornaby F.C", "O'Grady's"),
        "o grady s lost at thornaby" to setOf("O'Grady's", "Thornaby F.C"),
        "Grange B v Riverside B postponed" to setOf("Grange B", "Riverside B"),
        "the grange derby is on the 12th" to emptySet(),
    )
}
