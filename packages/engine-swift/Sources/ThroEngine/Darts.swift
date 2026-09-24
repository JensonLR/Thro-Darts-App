// Darts in a visit, read one at a time (OD-023). A line-for-line counterpart of Darts.kt.
//
// This is the engine's answer to *what have these darts done so far*, and it is public because a
// scoring screen asks it after every dart: what is left, whether the visit is already decided, and how
// many darts remain for a finish. A screen that works that out for itself is a second rulebook — and
// the iOS client had one: its per-dart entry sent the raw sum of the darts under double-in, so darts
// thrown before the opening double were scored.
//
// `Engine.apply` with `.recordDarts` is built on this and nothing else, so what a screen shows
// mid-visit and what is recorded at the end cannot disagree.

public enum Darts {

    /// How the darts so far leave the visit.
    public enum Settled: Sendable, Equatable { case scored, bust, legWon }

    /// Darts in a visit.
    public static let hand = 3

    /// See the Kotlin `Darts.Reading` for each field.
    public struct Reading: Equatable, Sendable {
        /// Nil while the visit is still open: fewer than three darts and nothing decided.
        public let settled: Settled?
        /// The index of the dart that bust or finished the visit.
        public let at: Int?
        public let bustReason: BustReason?
        /// The score after every counted dart, before any bust is applied. While the visit is open
        /// this is the score a screen shows and routes from.
        public let left: Int
        /// Points counted before the settling dart — what a keep-scored bust keeps.
        public let scoredBefore: Int
        /// Every point counted, a busting dart included: a visit-level record's total.
        public let counted: Int
        public let opened: Bool
        /// Darts thrown while the score in front of them was a one-dart finish.
        public let atDouble: Int
        /// Darts up to and including the settling one.
        public let thrown: Int

        /// Darts still in hand while the visit is open; none once it is decided.
        public var dartsLeft: Int { settled == nil ? Darts.hand - thrown : 0 }
    }

    /// Walks `darts` from `before`. Darts after the one that decides the visit are not read — they were
    /// never thrown — and `thrown` says how many were. A dart AT A DOUBLE is one thrown while the score
    /// in front of it is a one-dart finish under `outRule`; see the Kotlin for why that and not intent.
    public static func read(
        before: Int,
        darts: [Dart],
        outRule: OutRule,
        inRule: InRule = .straight,
        opened: Bool = true
    ) -> Reading {
        let atADouble = RuleTables.oneDartFinishes(outRule)
        var left = before
        var counted = 0
        var atDouble = 0
        var isOpen = opened
        for (i, dart) in darts.enumerated() {
            if i >= hand { break }
            if atADouble.contains(left) { atDouble += 1 }
            if !isOpen {
                if !dart.mayOpen(inRule) { continue }     // scores nothing: the player is not in
                isOpen = true
            }
            let after = left - dart.value
            let bust: BustReason?
            if after < 0 {
                bust = .BELOW_ZERO
            } else if after == 1 && outRule == .double {
                bust = .REMAINDER_ONE
            } else if after == 0 && !dart.mayFinish(outRule) {
                bust = .NOT_A_FINISHING_DART
            } else {
                bust = nil
            }
            if let bust {
                return Reading(settled: .bust, at: i, bustReason: bust, left: left, scoredBefore: counted,
                               counted: counted + dart.value, opened: isOpen, atDouble: atDouble, thrown: i + 1)
            }
            if after == 0 {
                return Reading(settled: .legWon, at: i, bustReason: nil, left: 0, scoredBefore: counted,
                               counted: counted + dart.value, opened: isOpen, atDouble: atDouble, thrown: i + 1)
            }
            left = after
            counted += dart.value
        }
        let thrown = min(darts.count, hand)
        return Reading(settled: thrown == hand ? .scored : nil, at: nil, bustReason: nil, left: left,
                       scoredBefore: counted, counted: counted, opened: isOpen, atDouble: atDouble,
                       thrown: thrown)
    }
}

/// Checkouts, as a function of the darts in hand (OD-023). Whether a finish exists is arithmetic;
/// which route THRØ suggests is a position (PD-013). Both come from the one generated route table,
/// which picks the fewest darts — so a route no longer than the hand is a finish that exists, and the
/// spec validator proves there is no finish in hand without one.
public enum Checkout {

    /// Fewest darts that finish `remaining` under `outRule`, or nil when three cannot.
    public static func dartsNeeded(_ remaining: Int, _ outRule: OutRule) -> Int? {
        RuleTables.route(remaining, outRule)?.count
    }

    /// Whether `remaining` can be finished with `dartsLeft` darts.
    public static func isPossible(_ remaining: Int, dartsLeft: Int, _ outRule: OutRule) -> Bool {
        guard let n = dartsNeeded(remaining, outRule) else { return false }
        return n <= dartsLeft
    }

    /// The route THRØ suggests with `dartsLeft` darts in hand, or nil when there is no finish with
    /// them. Never a route longer than the hand: on 100 with one dart left there is nothing to show.
    public static func route(_ remaining: Int, dartsLeft: Int, _ outRule: OutRule) -> [String]? {
        guard let r = RuleTables.route(remaining, outRule), r.count <= dartsLeft else { return nil }
        return r
    }
}
