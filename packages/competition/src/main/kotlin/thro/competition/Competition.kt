package thro.competition

/**
 * Competition structure: competitors, brackets and byes.
 *
 * The domain owns this arithmetic because the approved design got it wrong — an entry list of 74
 * was described as "Round of 64 with 10 byes", where 10 is the number of preliminary matches and
 * the real bye count is 54. A UI that carries these numbers will eventually carry a wrong one, so
 * it does not carry them at all.
 */

/** The entity that contests a match. Rating is always a property of the player, never of this. */
public sealed interface Competitor {
    public val id: String

    public data class Player(override val id: String) : Competitor
    public data class Pair(override val id: String, val players: List<String>) : Competitor
    public data class Team(override val id: String, val players: List<String>) : Competitor
}

/**
 * A bracket position. The approved design renders four different competitive facts identically as
 * "TBC", which makes a bye indistinguishable from an undecided slot or a withdrawal.
 */
public sealed interface Slot {
    public data class Filled(val competitor: Competitor, val seed: Int? = null) : Slot
    /** Awaiting the result of an earlier match. */
    public data object Undetermined : Slot
    /** Advanced without playing, because the bracket is larger than the field. */
    public data class Bye(val competitor: Competitor) : Slot
    /** Advanced because the opponent did not play. */
    public data class Walkover(val competitor: Competitor) : Slot
    public data class Withdrawn(val competitor: Competitor) : Slot
}

public data class BracketMath(
    val entrants: Int,
    /** The next power of two at or above [entrants]. */
    val bracketSize: Int,
    val byes: Int,
    val preliminaryMatches: Int,
) {
    init {
        require(byes + preliminaryMatches * 2 == entrants || entrants == 1) {
            "byes plus players in preliminaries must account for every entrant"
        }
        require(byes + preliminaryMatches == bracketSize / 2 || entrants == 1) {
            "byes plus preliminary winners must fill the first full round"
        }
    }
}

public object Bracket {

    /**
     * Bracket size is computed by bit length, never by a power-of-two formula over a logarithm.
     * A floating-point log2 returns a value fractionally above the integer for exact powers of two,
     * which silently doubles the bracket for 64, 128 and 256 — the inputs most likely to occur.
     */
    public fun sizeFor(entrants: Int): Int {
        require(entrants >= 1) { "a competition needs at least one entrant" }
        if (entrants == 1) return 1
        var size = 1
        while (size < entrants) size = size shl 1
        return size
    }

    /**
     * A bye **advances** a competitor without playing; it does not remove one. For 74 entrants the
     * bracket is 128, so 54 receive byes and the remaining 20 play 10 preliminary matches — whose
     * winners join the 54 to fill a round of 64.
     */
    public fun math(entrants: Int): BracketMath {
        val size = sizeFor(entrants)
        // A single entrant is degenerate but real: an organiser can have one person turn up. They
        // advance on a bye rather than the arithmetic falling over.
        if (entrants == 1) {
            return BracketMath(entrants = 1, bracketSize = 1, byes = 1, preliminaryMatches = 0)
        }
        val byes = size - entrants
        val prelimPlayers = entrants - byes
        return BracketMath(
            entrants = entrants,
            bracketSize = size,
            byes = byes,
            preliminaryMatches = prelimPlayers / 2,
        )
    }

    /**
     * Seeds the field so that byes go to the highest seeds, which is what the approved organiser
     * design specifies. Returns the first full round's slots in order.
     */
    public fun firstRound(seeded: List<Competitor>): List<Slot> {
        val m = math(seeded.size)
        val byeHolders = seeded.take(m.byes)
        return byeHolders.map { Slot.Bye(it) } + List(m.preliminaryMatches) { Slot.Undetermined }
    }
}

/** A league fixture is not a bracket slot: it has no parent, and it can be awarded unplayed. */
public sealed interface FixtureOutcome {
    public data class Played(val homeLegs: Int, val awayLegs: Int) : FixtureOutcome
    public data class Awarded(val toCompetitorId: String, val reason: String) : FixtureOutcome
    public data class Walkover(val toCompetitorId: String) : FixtureOutcome
    public data object Void : FixtureOutcome
}

public data class StandingsRow(
    val competitorId: String,
    val played: Int = 0,
    val won: Int = 0,
    val drawn: Int = 0,
    val lost: Int = 0,
    val legsFor: Int = 0,
    val legsAgainst: Int = 0,
    val points: Int = 0,
) {
    public val legDifference: Int get() = legsFor - legsAgainst
}

public enum class TieBreak { POINTS, LEG_DIFFERENCE, LEGS_FOR, HEAD_TO_HEAD, PLAYED }

/**
 * Standings ordering.
 *
 * The tie-break chain is declared per competition rather than hardcoded, and each row records the
 * chain step that actually separated it — so a published table can justify its own ordering. The
 * approved design's table exposes legs for and against but has no head-to-head column, which means
 * an ordering that used head-to-head could not be explained from the table shown.
 */
public data class RankedRow(val row: StandingsRow, val position: Int, val separatedBy: TieBreak?)

public object Standings {

    public fun rank(
        rows: List<StandingsRow>,
        chain: List<TieBreak> = listOf(TieBreak.POINTS, TieBreak.LEG_DIFFERENCE, TieBreak.LEGS_FOR),
        headToHead: (String, String) -> Int = { _, _ -> 0 },
    ): List<RankedRow> {
        val comparator = Comparator<StandingsRow> { a, b ->
            for (step in chain) {
                val c = compareStep(step, a, b, headToHead)
                if (c != 0) return@Comparator c
            }
            0
        }
        val sorted = rows.sortedWith(comparator)
        return sorted.mapIndexed { i, row ->
            val previous = sorted.getOrNull(i - 1)
            val by = previous?.let { p -> chain.firstOrNull { compareStep(it, p, row, headToHead) != 0 } }
            RankedRow(row, i + 1, by)
        }
    }

    private fun compareStep(
        step: TieBreak,
        a: StandingsRow,
        b: StandingsRow,
        headToHead: (String, String) -> Int,
    ): Int = when (step) {
        // descending: more is better
        TieBreak.POINTS -> b.points - a.points
        TieBreak.LEG_DIFFERENCE -> b.legDifference - a.legDifference
        TieBreak.LEGS_FOR -> b.legsFor - a.legsFor
        TieBreak.HEAD_TO_HEAD -> headToHead(b.competitorId, a.competitorId)
        TieBreak.PLAYED -> b.played - a.played
    }
}
