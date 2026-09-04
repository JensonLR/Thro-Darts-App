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

/** One recorded visit. [dartsUsed] null means unknown — never zero, never inferred. */
public data class VisitRecord(
    val legOrdinal: Int,
    val visitOrdinal: Int,
    val visitTotal: Int,
    val dartsUsed: Int?,
    val bust: Boolean,
    val remainingBefore: Int,
    val remainingAfter: Int,
    val wonLeg: Boolean,
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
        if (wins.isEmpty()) return Stat.unavailable("No leg has been won yet, so there is nothing to report.")
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
     * Checkout percentage needs doubles attempted. Nothing in a visit total distinguishes one dart
     * thrown at a double from three, so this cannot be computed — and a figure presented under this
     * name without dart-level evidence would be fabricated.
     */
    public fun checkoutPercentage(evidenceLevel: EvidenceLevel): Stat = when (evidenceLevel) {
        EvidenceLevel.VISIT_TOTAL -> Stat.unavailable(
            "Checkout percentage needs to know how many darts were thrown at a double. " +
                "This match recorded visit totals, so it cannot be calculated.",
        )
        EvidenceLevel.DART_LEVEL -> Stat.unavailable(
            "Dart-level scoring is not yet available.",
        )
    }

    /** Purely dart-level. No approximation exists, so none is offered. */
    public fun doublesHitRate(evidenceLevel: EvidenceLevel): Stat = checkoutPercentage(evidenceLevel)

    /**
     * The fewest visits taken to win a leg. Best leg *in darts* is not computable without the
     * winning visit's dart count, so the honest measure counts visits and says so.
     */
    public fun bestLegInVisits(visits: List<VisitRecord>): Stat {
        val wonLegs = visits.filter { it.wonLeg }.map { it.legOrdinal }.toSet()
        if (wonLegs.isEmpty()) return Stat.unavailable("No leg has been won yet, so there is nothing to report.")
        val counts = visits.filter { it.legOrdinal in wonLegs }.groupingBy { it.legOrdinal }.eachCount()
        return Stat.exact(counts.values.min().toDouble(), wonLegs.size)
    }
}
