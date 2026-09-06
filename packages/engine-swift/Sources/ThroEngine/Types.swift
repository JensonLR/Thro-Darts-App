// THRØ scoring domain — types, Swift.
//
// A faithful port of the Kotlin module under the same constraints: no floating point, no clock
// access, no randomness, no I/O, and no exceptions used for control flow. Anything
// non-deterministic — who threw first, what time it is — arrives as an input.
//
// Structural choices mirror the Kotlin deliberately. Where Swift would idiomatically differ (an
// enum with associated values instead of a sealed interface, say) the shape is kept parallel so
// that a reader comparing the two files can see they agree, which is the only practical defence
// against the divergence ADR-002 is worried about.

public struct PlayerId: Hashable, CustomStringConvertible, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }
    public var description: String { value }
}

public enum OutRule: String, Sendable { case double, master, straight }

public enum InRule: String, Sendable { case straight, double, master }

/// Whether the right to start alternates every leg, or only between sets. Real competitions differ.
public enum Alternation: Sendable { case perLeg, perSet }

public enum StructureMode: Sendable { case bestOf, firstTo }

/// - Parameters:
///   - clearBy: legs a competitor must lead by to take the unit. 1 for most formats, 2 for
///     two-clear-legs competitions.
///   - cap: an upper bound where a two-clear format would otherwise run indefinitely.
public struct Structure: Sendable {
    public let mode: StructureMode
    public let target: Int
    public let clearBy: Int
    public let cap: Int?

    public init(mode: StructureMode, target: Int, clearBy: Int = 1, cap: Int? = nil) {
        precondition(target > 0, "target must be positive")
        precondition(clearBy >= 1, "clearBy must be at least 1")
        self.mode = mode
        self.target = target
        self.clearBy = clearBy
        self.cap = cap
    }

    /// Wins needed under this structure. Best-of-9 needs 5; first-to-5 needs 5.
    public var winsRequired: Int {
        switch mode {
        case .firstTo: return target
        case .bestOf: return target / 2 + 1
        }
    }
}

public struct MatchFormat: Sendable {
    public let startingScore: Int
    public let inRule: InRule
    public let outRule: OutRule
    public let legs: Structure
    /// Nil means the match is decided on legs alone.
    public let sets: Structure?
    public let throwFirst: PlayerId
    public let alternation: Alternation

    public init(
        startingScore: Int,
        inRule: InRule,
        outRule: OutRule,
        legs: Structure,
        sets: Structure? = nil,
        throwFirst: PlayerId,
        alternation: Alternation = .perLeg
    ) {
        precondition(startingScore > 1, "starting score must exceed 1")
        self.startingScore = startingScore
        self.inRule = inRule
        self.outRule = outRule
        self.legs = legs
        self.sets = sets
        self.throwFirst = throwFirst
        self.alternation = alternation
    }
}

public enum Command: Sendable {
    /// - Parameters:
    ///   - dartsUsed: how many darts the visit consumed. Only ever ambiguous on a visit that wins a
    ///     leg, so it may be nil (unknown) or 3 on any other visit. Nil means *unknown* — never
    ///     zero, and never inferred.
    ///   - dartsAtDouble: how many of those darts were thrown at a double. Asked on **every** visit
    ///     that began on a checkout number, not only on one that finished: a player who was on a
    ///     finish and missed still attempted doubles, and those attempts are what make checkout
    ///     percentage computable at all. Nil means unknown; 0 means genuinely none were thrown.
    case recordVisit(player: PlayerId, visitTotal: Int, dartsUsed: Int?, dartsAtDouble: Int?)

    /// Swift does not allow default values on an enum case's associated values, so the convenience
    /// lives here instead. Both dart counts default to *unknown* rather than to a number, which is
    /// the whole point: absent must never quietly become zero.
    public static func visit(
        _ player: PlayerId,
        _ visitTotal: Int,
        dartsUsed: Int? = nil,
        dartsAtDouble: Int? = nil
    ) -> Command {
        .recordVisit(player: player, visitTotal: visitTotal, dartsUsed: dartsUsed, dartsAtDouble: dartsAtDouble)
    }
}

public enum RejectionReason: String, Sendable {
    case IMPOSSIBLE_VISIT_TOTAL
    case VISIT_TOTAL_OUT_OF_RANGE
    case DARTS_USED_INVALID
    case DARTS_AT_DOUBLE_INVALID
    case NOT_YOUR_TURN
    case MATCH_COMPLETE
}

public enum BustReason: String, Sendable { case BELOW_ZERO, REMAINDER_ONE, NOT_CHECKOUT_POSSIBLE }

public enum Effect: String, Sendable { case scored, bust, leg_won, set_won, match_won }

public enum Outcome: Sendable {
    case accepted(state: MatchState, effect: Effect, bustReason: BustReason?)
    /// A rejection is part of the contract, not an error: the UI renders it.
    case rejected(reason: RejectionReason)
}

public struct MatchState: Sendable {
    public let format: MatchFormat
    public let home: PlayerId
    public let away: PlayerId
    public var remaining: [PlayerId: Int]
    public var legsWonInSet: [PlayerId: Int]
    public var setsWon: [PlayerId: Int]
    public var legsWonTotal: [PlayerId: Int]
    public var currentSet: Int
    public var currentLeg: Int
    public var legStarter: PlayerId
    public var setStarter: PlayerId
    /// Nil once the match is complete.
    public var thrower: PlayerId?
    public var winner: PlayerId?
    public var visitsInLeg: Int

    public var isComplete: Bool { winner != nil }

    public func opponentOf(_ p: PlayerId) -> PlayerId { p == home ? away : home }

    public static func start(format: MatchFormat, home: PlayerId, away: PlayerId) -> MatchState {
        precondition(home != away, "a competitor cannot play itself")
        precondition(
            format.throwFirst == home || format.throwFirst == away,
            "throwFirst must be one of the competitors"
        )
        return MatchState(
            format: format,
            home: home,
            away: away,
            remaining: [home: format.startingScore, away: format.startingScore],
            legsWonInSet: [home: 0, away: 0],
            setsWon: [home: 0, away: 0],
            legsWonTotal: [home: 0, away: 0],
            currentSet: 1,
            currentLeg: 1,
            legStarter: format.throwFirst,
            setStarter: format.throwFirst,
            thrower: format.throwFirst,
            winner: nil,
            visitsInLeg: 0
        )
    }
}
