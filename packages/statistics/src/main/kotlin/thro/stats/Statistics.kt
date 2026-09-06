package thro.stats

/**
 * THRØ statistics.
 *
 * Separate from the scoring engine, deliberately: the engine deals in state transitions and
 * contains no floating point, while averages and rates need division. Keeping them apart is what
 * lets the engine stay exactly reproducible across platforms.
 *
 * The governing rule is that THRØ never invents dart-level evidence. A visit total of 100 does not
 * say which three darts were thrown, so any statistic that depends on knowing them is reported as
 * unavailable rather than approximated. Every value therefore carries **how it was arrived at**,
 * not just a number.
 */

/** How far a figure can be trusted. A statistic that cannot be computed says so. */
public enum class Basis {
    /** Derived with certainty from the recorded evidence. */
    EXACT,

    /** A defensible interval or a lower bound. Never presented as a point value. */
    BOUNDED,

    /** Not computable from the evidence held. Never approximated, never inferred. */
    UNAVAILABLE,
}

/** What class of evidence the figure rests on. */
public enum class EvidenceLevel { VISIT_TOTAL, DART_LEVEL }

/**
 * A statistic as it crosses the API. The [basis] is not decoration: a client must be able to render
 * an unavailable or approximate figure differently from an exact one, and a figure that silently
 * lost its qualification is the failure this type exists to prevent.
 */
public data class Stat(
    val basis: Basis,
    /** Null when [basis] is [Basis.UNAVAILABLE]. */
    val value: Double? = null,
    /** Present when [basis] is [Basis.BOUNDED]. */
    val lower: Double? = null,
    val upper: Double? = null,
    val evidenceLevel: EvidenceLevel = EvidenceLevel.VISIT_TOTAL,
    val sampleSize: Int = 0,
    /** Why it is unavailable or bounded, in terms a person can act on. */
    val note: String? = null,
) {
    public companion object {
        public fun exact(value: Double, n: Int): Stat =
            Stat(Basis.EXACT, value = value, sampleSize = n)

        public fun bounded(lower: Double, upper: Double, n: Int, note: String): Stat =
            Stat(Basis.BOUNDED, lower = lower, upper = upper, sampleSize = n, note = note)

        public fun unavailable(note: String): Stat = Stat(Basis.UNAVAILABLE, note = note)
    }
}

/**
 * One recorded visit. Null means **unknown** — never zero, never inferred.
 *
 * @param dartsAtDouble how many darts were thrown at a double. Recorded on every visit that began
 *   on a finish, whether or not it ended in one: a player on 40 who throws a single 20 and misses
 *   has attempted a double, and it is those attempts that make checkout percentage computable.
 */
public data class VisitRecord(
    val legOrdinal: Int,
    val visitOrdinal: Int,
    val visitTotal: Int,
    val dartsUsed: Int?,
    val bust: Boolean,
    val remainingBefore: Int,
    val remainingAfter: Int,
    val wonLeg: Boolean,
    val dartsAtDouble: Int? = null,
)

public object Statistics {

    // ---------------------------------------------------------------- exact from visit totals

    /** A maximum. 180 has exactly one decomposition, so a 180 visit total *is* dart-level proof. */
    public fun maximums(visits: List<VisitRecord>): Stat =
        Stat.exact(visits.count { it.visitTotal == 180 }.toDouble(), visits.size)

    public fun scoresAtLeast(visits: List<VisitRecord>, threshold: Int): Stat =
        Stat.exact(visits.count { it.visitTotal >= threshold }.toDouble(), visits.size)

    /** The value finished from, which is the remaining at the start of the winning visit. */
    public fun highestCheckout(visits: List<VisitRecord>): Stat {
        val wins = visits.filter { it.wonLeg }
        if (wins.isEmpty()) return Stat.unavailable("This player has not won a leg, so there is no checkout to report.")
        return Stat.exact(wins.maxOf { it.remainingBefore }.toDouble(), wins.size)
    }

    /**
     * Legs won from the first visit that opened on a finishable number, over all such openings.
     *
     * This is **not** checkout percentage and must never carry that label. Checkout percentage needs
     * doubles attempted, which visit totals cannot supply. This measures something adjacent, real,
     * and exactly computable — so it gets its own name.
     */
    public fun finishRateFromCheckablePosition(
        visits: List<VisitRecord>,
        checkable: Set<Int>,
    ): Stat {
        val opportunities = visits.filter { it.remainingBefore in checkable }
        if (opportunities.isEmpty()) {
            return Stat.unavailable("No visit has yet opened on a finishable number.")
        }
        val taken = opportunities.count { it.wonLeg }
        return Stat.exact(taken.toDouble() * 100 / opportunities.size, opportunities.size)
    }

    // ---------------------------------------------------------------- exact only with darts used

    /**
     * Points per three darts.
     *
     * Every visit uses three darts except the one that wins a leg, which may have used one or two.
     * With that captured this is exact; without it the denominator is overstated and the average
     * runs low — so it is returned as an interval rather than a point value that would read as fact.
     */
    public fun threeDartAverage(visits: List<VisitRecord>): Stat {
        if (visits.isEmpty()) return Stat.unavailable("No visits have been recorded for this match yet.")
        val scored = visits.sumOf { if (it.bust) 0 else it.visitTotal }
        val wins = visits.filter { it.wonLeg }
        val unknownWins = wins.count { it.dartsUsed == null }

        if (unknownWins == 0) {
            val darts = visits.sumOf { it.dartsUsed ?: 3 }
            return Stat.exact(scored.toDouble() * 3 / darts, visits.size)
        }

        // Known darts, plus the widest and narrowest the unknown winning visits could be.
        val known = visits.filter { !(it.wonLeg && it.dartsUsed == null) }.sumOf { it.dartsUsed ?: 3 }
        val most = known + unknownWins * 3   // most darts -> lowest average
        val least = known + unknownWins * 1  // fewest darts -> highest average
        return Stat.bounded(
            lower = scored.toDouble() * 3 / most,
            upper = scored.toDouble() * 3 / least,
            n = visits.size,
            note = "$unknownWins leg-winning visit(s) did not record how many darts were used, " +
                "so the exact figure lies in this range.",
        )
    }

    /**
     * Average over the first three visits of a leg.
     *
     * Legs decided in fewer than three visits have no first nine, so they are excluded and the
     * denominator is disclosed rather than hidden — excluding them silently would drop exactly the
     * legs against the fastest opponents.
     */
    public fun firstNineAverage(visits: List<VisitRecord>): Stat {
        val byLeg = visits.groupBy { it.legOrdinal }
        val qualifying = byLeg.filter { (_, v) -> v.size >= 3 }
        if (qualifying.isEmpty()) {
            return Stat.unavailable("No leg has yet reached nine darts, so there is no first nine.")
        }
        val scored = qualifying.values.sumOf { legVisits ->
            legVisits.sortedBy { it.visitOrdinal }.take(3).sumOf { if (it.bust) 0 else it.visitTotal }
        }
        val darts = qualifying.size * 9
        return Stat(
            basis = Basis.EXACT,
            value = scored.toDouble() * 3 / darts,
            sampleSize = qualifying.size,
            note = if (qualifying.size < byLeg.size) {
                "${byLeg.size - qualifying.size} leg(s) ended before nine darts and are excluded."
            } else {
                null
            },
        )
    }

    // ---------------------------------------------------------------- not computable, and said so

    /**
     * Doubles hit as a percentage of doubles thrown at — the broadcast definition.
     *
     * A visit total alone cannot supply this, but a scorer can: when a player is on a finish, the
     * app asks how many darts went at a double, whether or not they took it. That single question
     * is the whole difference between this being computable and not.
     *
     * Under double-out every leg is won on a double, so hits equal legs won and the only unknown is
     * attempts. Where a checkable visit did not record its attempts the figure is **bounded**, not
     * guessed: unrecorded attempts can only lower the true percentage, so the recorded figure is
     * its upper bound.
     */
    public fun checkoutPercentage(visits: List<VisitRecord>, checkable: Set<Int>): Stat {
        val onAFinish = visits.filter { it.remainingBefore in checkable }
        if (onAFinish.isEmpty()) {
            return Stat.unavailable("No visit has yet begun on a finishable number.")
        }
        val recorded = onAFinish.filter { it.dartsAtDouble != null }
        if (recorded.isEmpty()) {
            return Stat.unavailable(
                "No visit recorded how many darts were thrown at a double, so checkout " +
                    "percentage cannot be calculated for this match.",
            )
        }
        val hits = visits.count { it.wonLeg }
        val known = recorded.sumOf { it.dartsAtDouble ?: 0 }
        val unknownVisits = onAFinish.size - recorded.size
        if (known == 0) {
            return Stat.unavailable("No darts have yet been thrown at a double.")
        }
        if (unknownVisits == 0) {
            return Stat(
                basis = Basis.EXACT,
                value = hits.toDouble() * 100 / known,
                evidenceLevel = EvidenceLevel.DART_LEVEL,
                sampleSize = known,
            )
        }
        // Bound the unrecorded attempts from both sides. An unrecorded visit threw at most three
        // darts at a double; and under double-out one that *won* threw at least one, since the
        // winning dart is itself a double. Without that second fact the upper bound can exceed
        // 100%: a leg-winning visit whose attempts went unrecorded would count in the numerator
        // while contributing nothing to the denominator.
        val unrecordedWins = onAFinish.count { it.dartsAtDouble == null && it.wonLeg }
        return Stat.bounded(
            lower = hits.toDouble() * 100 / (known + unknownVisits * 3),
            upper = hits.toDouble() * 100 / (known + unrecordedWins),
            n = known,
            note = "$unknownVisits visit(s) on a finish did not record their darts at a double, " +
                "so the exact figure lies in this range.",
        ).copy(evidenceLevel = EvidenceLevel.DART_LEVEL)
    }

    /** The same quantity under its other common name. */
    public fun doublesHitRate(visits: List<VisitRecord>, checkable: Set<Int>): Stat =
        checkoutPercentage(visits, checkable)

    /** Total darts thrown at a double. Exact over the visits that recorded it. */
    /**
     * How many darts were thrown at a double.
     *
     * This needs [checkable] to be honest. Without it the only available answer is "how many were
     * *recorded*", and reporting that as exact would state a match total that is really a partial
     * count — the precise confusion PD-001 exists to prevent. Knowing which visits stood on a
     * finish is what separates "did not attempt" from "did not say".
     */
    public fun doublesAttempted(visits: List<VisitRecord>, checkable: Set<Int>): Stat {
        val onAFinish = visits.filter { it.remainingBefore in checkable }
        val recorded = onAFinish.filter { it.dartsAtDouble != null }
        if (recorded.isEmpty()) {
            // Two different reasons, and telling a player the wrong one is its own small lie:
            // never having stood on a finish is a fact about the match, not missing evidence.
            return Stat.unavailable(
                if (onAFinish.isEmpty()) {
                    "No visit has yet begun on a finishable number, so no double has been thrown at."
                } else {
                    "No visit has recorded its darts at a double."
                },
            )
        }
        val known = recorded.sumOf { it.dartsAtDouble ?: 0 }
        val unknownVisits = onAFinish.size - recorded.size
        if (unknownVisits == 0) return Stat.exact(known.toDouble(), recorded.size)
        // an unrecorded visit threw at least one dart at a double if it won the leg, at most three
        val floor = known + onAFinish.count { it.dartsAtDouble == null && it.wonLeg }
        return Stat.bounded(
            lower = floor.toDouble(),
            upper = (known + unknownVisits * 3).toDouble(),
            n = recorded.size,
            note = "$unknownVisits visit(s) on a finish did not record their darts at a double, " +
                "so the total is at least $floor and at most ${known + unknownVisits * 3}.",
        )
    }

    /**
     * The fewest visits taken to win a leg. Best leg *in darts* is not computable without the
     * winning visit's dart count, so the honest measure counts visits and says so.
     */
    public fun bestLegInVisits(visits: List<VisitRecord>): Stat {
        val wonLegs = visits.filter { it.wonLeg }.map { it.legOrdinal }.toSet()
        if (wonLegs.isEmpty()) return Stat.unavailable("This player has not won a leg, so there is no best leg to report.")
        val counts = visits.filter { it.legOrdinal in wonLegs }.groupingBy { it.legOrdinal }.eachCount()
        return Stat.exact(counts.values.min().toDouble(), wonLegs.size)
    }
}
