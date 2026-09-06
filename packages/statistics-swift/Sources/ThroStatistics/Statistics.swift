// THRØ statistics — Swift.
//
// A faithful port of packages/statistics (Kotlin). Separate from the scoring engine, deliberately:
// the engine deals in state transitions and contains no floating point, while averages and rates
// need division. Keeping them apart is what lets the engine stay exactly reproducible across
// platforms.
//
// The governing rule is that THRØ never invents dart-level evidence. A visit total of 100 does not
// say which three darts were thrown, so any statistic that depends on knowing them is reported as
// unavailable rather than approximated. Every value therefore carries HOW it was arrived at, not
// just a number.
//
// Function bodies and, in particular, the explanatory notes are kept identical to the Kotlin: the
// tests assert on the wording, because a note is what a player reads when a figure is missing.

/// How far a figure can be trusted. A statistic that cannot be computed says so.
public enum Basis: String, Equatable, Sendable {
    /// Derived with certainty from the recorded evidence.
    case exact = "EXACT"
    /// A defensible interval or a lower bound. Never presented as a point value.
    case bounded = "BOUNDED"
    /// Not computable from the evidence held. Never approximated, never inferred.
    case unavailable = "UNAVAILABLE"
}

/// What class of evidence the figure rests on.
public enum EvidenceLevel: String, Equatable, Sendable {
    case visitTotal = "VISIT_TOTAL"
    case dartLevel = "DART_LEVEL"
}

/// A statistic as it crosses a boundary. The basis is not decoration: a view must render an
/// unavailable or approximate figure differently from an exact one, and a figure that silently
/// lost its qualification is the failure this type exists to prevent.
public struct Stat: Equatable, Sendable {
    public let basis: Basis
    /// Nil when `basis` is `.unavailable`, and nil when it is `.bounded` — a range is not a point.
    public let value: Double?
    /// Present when `basis` is `.bounded`.
    public let lower: Double?
    public let upper: Double?
    public let evidenceLevel: EvidenceLevel
    public let sampleSize: Int
    /// Why it is unavailable or bounded, in terms a person can act on.
    public let note: String?

    public init(
        basis: Basis,
        value: Double? = nil,
        lower: Double? = nil,
        upper: Double? = nil,
        evidenceLevel: EvidenceLevel = .visitTotal,
        sampleSize: Int = 0,
        note: String? = nil
    ) {
        self.basis = basis
        self.value = value
        self.lower = lower
        self.upper = upper
        self.evidenceLevel = evidenceLevel
        self.sampleSize = sampleSize
        self.note = note
    }

    public static func exact(_ value: Double, n: Int) -> Stat {
        Stat(basis: .exact, value: value, sampleSize: n)
    }

    public static func bounded(lower: Double, upper: Double, n: Int, note: String) -> Stat {
        Stat(basis: .bounded, lower: lower, upper: upper, sampleSize: n, note: note)
    }

    public static func unavailable(_ note: String) -> Stat {
        Stat(basis: .unavailable, note: note)
    }

    /// The Kotlin `copy(evidenceLevel = …)`.
    public func with(evidenceLevel level: EvidenceLevel) -> Stat {
        Stat(basis: basis, value: value, lower: lower, upper: upper,
             evidenceLevel: level, sampleSize: sampleSize, note: note)
    }
}

/// One recorded visit. Nil means **unknown** — never zero, never inferred.
///
/// `dartsAtDouble` is how many darts were thrown at a double. Recorded on every visit that began on
/// a finish, whether or not it ended in one: a player on 40 who throws a single 20 and misses has
/// attempted a double, and it is those attempts that make checkout percentage computable.
public struct VisitRecord: Equatable, Sendable {
    public let legOrdinal: Int
    public let visitOrdinal: Int
    public let visitTotal: Int
    public let dartsUsed: Int?
    public let bust: Bool
    public let remainingBefore: Int
    public let remainingAfter: Int
    public let wonLeg: Bool
    public let dartsAtDouble: Int?

    public init(
        legOrdinal: Int,
        visitOrdinal: Int,
        visitTotal: Int,
        dartsUsed: Int?,
        bust: Bool,
        remainingBefore: Int,
        remainingAfter: Int,
        wonLeg: Bool,
        dartsAtDouble: Int? = nil
    ) {
        self.legOrdinal = legOrdinal
        self.visitOrdinal = visitOrdinal
        self.visitTotal = visitTotal
        self.dartsUsed = dartsUsed
        self.bust = bust
        self.remainingBefore = remainingBefore
        self.remainingAfter = remainingAfter
        self.wonLeg = wonLeg
        self.dartsAtDouble = dartsAtDouble
    }

    /// The Kotlin `copy(dartsAtDouble = …)`, which the tests use to strip evidence.
    public func with(dartsAtDouble: Int?) -> VisitRecord {
        VisitRecord(legOrdinal: legOrdinal, visitOrdinal: visitOrdinal, visitTotal: visitTotal,
                    dartsUsed: dartsUsed, bust: bust, remainingBefore: remainingBefore,
                    remainingAfter: remainingAfter, wonLeg: wonLeg, dartsAtDouble: dartsAtDouble)
    }
}

public enum Statistics {

    // MARK: - exact from visit totals

    /// A maximum. 180 has exactly one decomposition, so a 180 visit total *is* dart-level proof.
    public static func maximums(_ visits: [VisitRecord]) -> Stat {
        Stat.exact(Double(visits.filter { $0.visitTotal == 180 }.count), n: visits.count)
    }

    public static func scoresAtLeast(_ visits: [VisitRecord], threshold: Int) -> Stat {
        Stat.exact(Double(visits.filter { $0.visitTotal >= threshold }.count), n: visits.count)
    }

    /// The value finished from, which is the remaining at the start of the winning visit.
    public static func highestCheckout(_ visits: [VisitRecord]) -> Stat {
        let wins = visits.filter { $0.wonLeg }
        guard let best = wins.map({ $0.remainingBefore }).max() else {
            return .unavailable("This player has not won a leg, so there is no checkout to report.")
        }
        return .exact(Double(best), n: wins.count)
    }

    /// Legs won from the first visit that opened on a finishable number, over all such openings.
    ///
    /// This is **not** checkout percentage and must never carry that label. Checkout percentage needs
    /// doubles attempted, which visit totals cannot supply. This measures something adjacent, real,
    /// and exactly computable — so it gets its own name.
    public static func finishRateFromCheckablePosition(_ visits: [VisitRecord], checkable: Set<Int>) -> Stat {
        let opportunities = visits.filter { checkable.contains($0.remainingBefore) }
        if opportunities.isEmpty {
            return .unavailable("No visit has yet opened on a finishable number.")
        }
        let taken = opportunities.filter { $0.wonLeg }.count
        return .exact(Double(taken) * 100 / Double(opportunities.count), n: opportunities.count)
    }

    // MARK: - exact only with darts used

    /// Points per three darts.
    ///
    /// Every visit uses three darts except the one that wins a leg, which may have used one or two.
    /// With that captured this is exact; without it the denominator is overstated and the average
    /// runs low — so it is returned as an interval rather than a point value that would read as fact.
    public static func threeDartAverage(_ visits: [VisitRecord]) -> Stat {
        if visits.isEmpty {
            return .unavailable("No visits have been recorded for this match yet.")
        }
        let scored = visits.reduce(0) { $0 + ($1.bust ? 0 : $1.visitTotal) }
        let unknownWins = visits.filter { $0.wonLeg && $0.dartsUsed == nil }.count

        if unknownWins == 0 {
            let darts = visits.reduce(0) { $0 + ($1.dartsUsed ?? 3) }
            return .exact(Double(scored) * 3 / Double(darts), n: visits.count)
        }

        // Known darts, plus the widest and narrowest the unknown winning visits could be.
        let known = visits
            .filter { !($0.wonLeg && $0.dartsUsed == nil) }
            .reduce(0) { $0 + ($1.dartsUsed ?? 3) }
        let most = known + unknownWins * 3   // most darts -> lowest average
        let least = known + unknownWins * 1  // fewest darts -> highest average
        return .bounded(
            lower: Double(scored) * 3 / Double(most),
            upper: Double(scored) * 3 / Double(least),
            n: visits.count,
            note: "\(unknownWins) leg-winning visit(s) did not record how many darts were used, "
                + "so the exact figure lies in this range."
        )
    }

    /// Average over the first three visits of a leg.
    ///
    /// Legs decided in fewer than three visits have no first nine, so they are excluded and the
    /// denominator is disclosed rather than hidden — excluding them silently would drop exactly the
    /// legs against the fastest opponents.
    public static func firstNineAverage(_ visits: [VisitRecord]) -> Stat {
        let byLeg = Dictionary(grouping: visits, by: { $0.legOrdinal })
        let qualifying = byLeg.filter { $0.value.count >= 3 }
        if qualifying.isEmpty {
            return .unavailable("No leg has yet reached nine darts, so there is no first nine.")
        }
        let scored = qualifying.values.reduce(0) { acc, legVisits in
            acc + legVisits
                .sorted { $0.visitOrdinal < $1.visitOrdinal }
                .prefix(3)
                .reduce(0) { $0 + ($1.bust ? 0 : $1.visitTotal) }
        }
        let darts = qualifying.count * 9
        let excluded = byLeg.count - qualifying.count
        return Stat(
            basis: .exact,
            value: Double(scored) * 3 / Double(darts),
            sampleSize: qualifying.count,
            note: excluded > 0 ? "\(excluded) leg(s) ended before nine darts and are excluded." : nil
        )
    }

    // MARK: - not computable, and said so

    /// Doubles hit as a percentage of doubles thrown at — the broadcast definition.
    ///
    /// A visit total alone cannot supply this, but a scorer can: when a player is on a finish, the
    /// app asks how many darts went at a double, whether or not they took it. That single question
    /// is the whole difference between this being computable and not.
    ///
    /// Under double-out every leg is won on a double, so hits equal legs won and the only unknown is
    /// attempts. Where a checkable visit did not record its attempts the figure is **bounded**, not
    /// guessed: unrecorded attempts can only lower the true percentage, so the recorded figure is
    /// its upper bound.
    public static func checkoutPercentage(_ visits: [VisitRecord], checkable: Set<Int>) -> Stat {
        let onAFinish = visits.filter { checkable.contains($0.remainingBefore) }
        if onAFinish.isEmpty {
            return .unavailable("No visit has yet begun on a finishable number.")
        }
        let recorded = onAFinish.filter { $0.dartsAtDouble != nil }
        if recorded.isEmpty {
            return .unavailable(
                "No visit recorded how many darts were thrown at a double, so checkout "
                + "percentage cannot be calculated for this match."
            )
        }
        let hits = visits.filter { $0.wonLeg }.count
        let known = recorded.reduce(0) { $0 + ($1.dartsAtDouble ?? 0) }
        let unknownVisits = onAFinish.count - recorded.count
        if known == 0 {
            return .unavailable("No darts have yet been thrown at a double.")
        }
        if unknownVisits == 0 {
            return Stat(
                basis: .exact,
                value: Double(hits) * 100 / Double(known),
                evidenceLevel: .dartLevel,
                sampleSize: known
            )
        }
        // Bound the unrecorded attempts from both sides. An unrecorded visit threw at most three
        // darts at a double; and under double-out one that *won* threw at least one, since the
        // winning dart is itself a double. Without that second fact the upper bound can exceed
        // 100%: a leg-winning visit whose attempts went unrecorded would count in the numerator
        // while contributing nothing to the denominator.
        let unrecordedWins = onAFinish.filter { $0.dartsAtDouble == nil && $0.wonLeg }.count
        return Stat.bounded(
            lower: Double(hits) * 100 / Double(known + unknownVisits * 3),
            upper: Double(hits) * 100 / Double(known + unrecordedWins),
            n: known,
            note: "\(unknownVisits) visit(s) on a finish did not record their darts at a double, "
                + "so the exact figure lies in this range."
        ).with(evidenceLevel: .dartLevel)
    }

    /// The same quantity under its other common name.
    public static func doublesHitRate(_ visits: [VisitRecord], checkable: Set<Int>) -> Stat {
        checkoutPercentage(visits, checkable: checkable)
    }

    /// How many darts were thrown at a double.
    ///
    /// This needs `checkable` to be honest. Without it the only available answer is "how many were
    /// *recorded*", and reporting that as exact would state a match total that is really a partial
    /// count — the precise confusion PD-001 exists to prevent. Knowing which visits stood on a
    /// finish is what separates "did not attempt" from "did not say".
    public static func doublesAttempted(_ visits: [VisitRecord], checkable: Set<Int>) -> Stat {
        let onAFinish = visits.filter { checkable.contains($0.remainingBefore) }
        let recorded = onAFinish.filter { $0.dartsAtDouble != nil }
        if recorded.isEmpty {
            // Two different reasons, and telling a player the wrong one is its own small lie:
            // never having stood on a finish is a fact about the match, not missing evidence.
            return .unavailable(
                onAFinish.isEmpty
                    ? "No visit has yet begun on a finishable number, so no double has been thrown at."
                    : "No visit has recorded its darts at a double."
            )
        }
        let known = recorded.reduce(0) { $0 + ($1.dartsAtDouble ?? 0) }
        let unknownVisits = onAFinish.count - recorded.count
        if unknownVisits == 0 { return .exact(Double(known), n: recorded.count) }
        // an unrecorded visit threw at least one dart at a double if it won the leg, at most three
        let floor = known + onAFinish.filter { $0.dartsAtDouble == nil && $0.wonLeg }.count
        let ceiling = known + unknownVisits * 3
        return .bounded(
            lower: Double(floor),
            upper: Double(ceiling),
            n: recorded.count,
            note: "\(unknownVisits) visit(s) on a finish did not record their darts at a double, "
                + "so the total is at least \(floor) and at most \(ceiling)."
        )
    }

    /// The fewest visits taken to win a leg. Best leg *in darts* is not computable without the
    /// winning visit's dart count, so the honest measure counts visits and says so.
    public static func bestLegInVisits(_ visits: [VisitRecord]) -> Stat {
        let wonLegs = Set(visits.filter { $0.wonLeg }.map { $0.legOrdinal })
        if wonLegs.isEmpty {
            return .unavailable("This player has not won a leg, so there is no best leg to report.")
        }
        let counts = Dictionary(grouping: visits.filter { wonLegs.contains($0.legOrdinal) }, by: { $0.legOrdinal })
            .mapValues { $0.count }
        return .exact(Double(counts.values.min() ?? 0), n: wonLegs.count)
    }
}
