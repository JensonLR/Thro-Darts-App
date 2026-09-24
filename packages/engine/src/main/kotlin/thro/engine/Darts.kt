package thro.engine

/**
 * Darts in a visit, read one at a time (OD-023).
 *
 * This is the engine's answer to *what have these darts done so far*, and it is public because a
 * scoring screen asks it after every dart: what is left, whether the visit is already decided, and
 * how many darts remain for a finish. A screen that works that out for itself is a second rulebook,
 * and the repository has already paid for one of those (a per-dart entry that sent the raw sum of the
 * darts under double-in, so darts before the opening double were scored).
 *
 * The engine's own transition ([Engine.apply] with [Command.RecordDarts]) is built on this and
 * nothing else, so what a screen shows mid-visit and what is recorded at the end cannot disagree.
 */
public object Darts {

    /** How the darts so far leave the visit. */
    public enum class Settled { SCORED, BUST, LEG_WON }

    /**
     * @param settled null while the visit is still open: fewer than three darts and nothing decided.
     * @param at the index of the dart that bust or finished the visit.
     * @param left the score after every counted dart, before any bust is applied. While the visit is
     *   open this is the score a screen should show and route from.
     * @param scoredBefore the points counted before the settling dart — what a keep-scored bust keeps.
     * @param counted every point counted, the busting dart included: a visit-level record's total.
     * @param opened whether the player is in after these darts.
     * @param atDouble darts thrown while the score in front of them was a one-dart finish.
     * @param thrown the darts up to and including the settling one. Fewer than were given means some
     *   were entered after the visit was already over.
     */
    public data class Reading(
        val settled: Settled?,
        val at: Int?,
        val bustReason: BustReason?,
        val left: Int,
        val scoredBefore: Int,
        val counted: Int,
        val opened: Boolean,
        val atDouble: Int,
        val thrown: Int,
    ) {
        /** Darts still in hand while the visit is open; none once it is decided. */
        public val dartsLeft: Int get() = if (settled == null) HAND - thrown else 0
    }

    /** Darts in a visit. */
    public const val HAND: Int = 3

    /**
     * Walks [darts] from [before]. Darts after the one that decides the visit are not read — they
     * were never thrown — and [Reading.thrown] says how many were.
     *
     * A dart AT A DOUBLE is one thrown while the score in front of it is a one-dart finish under
     * [outRule]. That is observable from the darts and is what a scorer writes down. What the player
     * aimed at is not observable, and THRØ does not pretend it is: a player on 32 who throws a single
     * 16 has thrown one dart at a double and is now on 16 with another. It is counted before the
     * in-rule is consulted, because a player not yet in who stands on a one-dart finish can only open
     * with the dart that also finishes.
     */
    public fun read(
        before: Int,
        darts: List<Dart>,
        outRule: OutRule,
        inRule: InRule = InRule.STRAIGHT,
        opened: Boolean = true,
    ): Reading {
        val atADouble = RuleTables.oneDartFinishes(outRule)
        var left = before
        var counted = 0
        var atDouble = 0
        var isOpen = opened
        for ((i, dart) in darts.withIndex()) {
            if (i >= HAND) break
            if (left in atADouble) atDouble++
            if (!isOpen) {
                if (!dart.mayOpen(inRule)) continue      // scores nothing: the player is not in
                isOpen = true
            }
            val after = left - dart.value
            val bust = when {
                after < 0 -> BustReason.BELOW_ZERO
                after == 1 && outRule == OutRule.DOUBLE -> BustReason.REMAINDER_ONE
                after == 0 && !dart.mayFinish(outRule) -> BustReason.NOT_A_FINISHING_DART
                else -> null
            }
            if (bust != null) {
                return Reading(Settled.BUST, i, bust, left, counted, counted + dart.value, isOpen, atDouble, i + 1)
            }
            if (after == 0) {
                return Reading(Settled.LEG_WON, i, null, 0, counted, counted + dart.value, isOpen, atDouble, i + 1)
            }
            left = after
            counted += dart.value
        }
        val thrown = minOf(darts.size, HAND)
        return Reading(
            settled = if (thrown == HAND) Settled.SCORED else null,
            at = null, bustReason = null, left = left, scoredBefore = counted, counted = counted,
            opened = isOpen, atDouble = atDouble, thrown = thrown,
        )
    }
}

/**
 * Checkouts, as a function of the darts in hand (OD-023).
 *
 * Two different questions, kept apart because only one of them is a fact:
 *  - **whether** a finish exists with the darts left — arithmetic, and never wrong;
 *  - **which** route THRØ suggests — a position (PD-013), derived by a stated rule.
 *
 * Both come from the one generated route table. It picks the fewest darts, so a route no longer than
 * the darts in hand is a finish that exists, and there is no finish in hand without one; the spec
 * validator proves that for every remaining, every rule and one, two and three darts.
 */
public object Checkout {

    /** Fewest darts that finish [remaining] under [outRule], or null when three cannot. */
    public fun dartsNeeded(remaining: Int, outRule: OutRule): Int? = RuleTables.route(remaining, outRule)?.size

    /** Whether [remaining] can be finished with [dartsLeft] darts. */
    public fun isPossible(remaining: Int, dartsLeft: Int, outRule: OutRule): Boolean =
        dartsNeeded(remaining, outRule)?.let { it <= dartsLeft } ?: false

    /**
     * The route THRØ suggests with [dartsLeft] darts in hand, or null when there is no finish with
     * them. Never a route longer than the hand: on 100 with one dart left there is nothing to show.
     */
    public fun route(remaining: Int, dartsLeft: Int, outRule: OutRule): List<String>? =
        RuleTables.route(remaining, outRule)?.takeIf { it.size <= dartsLeft }
}
