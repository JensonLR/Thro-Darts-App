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

public enum InRule: String, Sendable {
    case straight, double, master

    /// Whether a player must open before anything scores.
    ///
    /// The engine scores a visit, not a dart, so this needed a capture rule before it could be
    /// scored honestly at all. PD-008 settled it: what a visit records while the player has not
    /// opened is the score FROM the opening dart onward, and zero means they did not open. That is
    /// what the scorer calls at the oche, it costs no statistic — a visit is three darts either way
    /// — and a non-zero total no opening sequence can make is refused.
    public var requiresOpening: Bool { self != .straight }
}

/// What a bust does to the score (OD-023). Declared on the match, never inferred, and never a
/// condition written into a screen: the engine is the only place that reads it.
public enum BustRule: String, Sendable, CaseIterable {
    /// The standard rule. The visit counts for nothing and the score returns to what it was when the
    /// visit began. On 40, a 20 then a D15 leaves 40.
    case restoreVisit
    /// A local rule some pub leagues play: the darts scored before the busting dart stand, and only
    /// the busting dart counts for nothing. On 40, a 20 then a D15 leaves 20.
    ///
    /// Only the darts can say what came before the bust, so under this rule a visit that busts must
    /// be recorded as darts; a busting total is refused as `DARTS_REQUIRED`.
    case keepScoredDarts
}

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
    public let bustRule: BustRule

    public init(
        startingScore: Int,
        inRule: InRule,
        outRule: OutRule,
        legs: Structure,
        sets: Structure? = nil,
        throwFirst: PlayerId,
        alternation: Alternation = .perLeg,
        bustRule: BustRule = .restoreVisit
    ) {
        precondition(startingScore > 1, "starting score must exceed 1")
        self.startingScore = startingScore
        self.inRule = inRule
        self.outRule = outRule
        self.legs = legs
        self.sets = sets
        self.throwFirst = throwFirst
        self.alternation = alternation
        self.bustRule = bustRule
    }
}

/// The part of the board a dart landed in.
public enum Ring: String, Sendable, CaseIterable { case miss, single, double, treble }

/// One dart, as it landed (OD-023).
///
/// A dart is decided by its RING, never by its value: a single 20 and a double 10 both score 20, and
/// only one of them finishes a double-out leg. That is the whole reason the engine takes darts at all.
///
/// `number` is 1...20 or 25 (the bull's number), and 0 for a miss. The inner bull is `Dart(25, .double)`
/// and scores 50; the outer bull is `Dart(25, .single)` and scores 25. A dart that is not on the board —
/// a treble bull, a double nought — can be constructed, is `isOnTheBoard` false, and is refused by the
/// engine as `DART_INVALID` rather than trapping.
public struct Dart: Hashable, Sendable, CustomStringConvertible {
    public let number: Int
    public let ring: Ring

    public init(_ number: Int, _ ring: Ring) {
        self.number = number
        self.ring = ring
    }

    public static let bullNumber = 25
    public static let miss = Dart(0, .miss)
    public static let bull = Dart(bullNumber, .double)
    public static let outerBull = Dart(bullNumber, .single)

    public var isOnTheBoard: Bool {
        switch ring {
        case .miss: return number == 0
        case .single, .double: return (1...20).contains(number) || number == Dart.bullNumber
        case .treble: return (1...20).contains(number)
        }
    }

    public var value: Int {
        switch ring {
        case .miss: return 0
        case .single: return number
        case .double: return 2 * number
        case .treble: return 3 * number
        }
    }

    /// Whether this dart may end a leg under `outRule`. The bull is a double.
    public func mayFinish(_ outRule: OutRule) -> Bool {
        switch outRule {
        case .double: return ring == .double
        case .master: return ring == .double || ring == .treble
        case .straight: return value > 0
        }
    }

    /// Whether this dart may open a leg under `inRule`. The same rings as finishing, for the same reason.
    public func mayOpen(_ inRule: InRule) -> Bool {
        switch inRule {
        case .double: return ring == .double
        case .master: return ring == .double || ring == .treble
        case .straight: return value > 0
        }
    }

    /// The name a scorer says, and the one the route table uses: T20, D16, 20, 25, Bull, Miss.
    public var name: String {
        if ring == .miss { return "Miss" }
        if number == Dart.bullNumber && ring == .double { return "Bull" }
        if number == Dart.bullNumber && ring == .single { return "25" }
        switch ring {
        case .single: return "\(number)"
        case .double: return "D\(number)"
        default: return "T\(number)"
        }
    }

    public var description: String { name }

    /// Reads a dart's name — the inverse of `name`. Syntactic only: `T25` parses to a dart that is not
    /// on the board, so the refusal is the engine's and carries its reason. Nil for text that is not a
    /// dart's name at all.
    public static func parse(_ text: String) -> Dart? {
        // Spaces trimmed by hand: this package imports nothing, so it builds wherever Swift does.
        let t = String(String(text.drop(while: { $0 == " " }).reversed()).drop(while: { $0 == " " }).reversed())
        switch t {
        case "Miss", "0": return .miss
        case "Bull", "D25": return .bull
        case "25", "S25": return .outerBull
        default: break
        }
        var ring = Ring.single
        var digits = Substring(t)
        switch t.first {
        case "S": ring = .single; digits = digits.dropFirst()
        case "D": ring = .double; digits = digits.dropFirst()
        case "T": ring = .treble; digits = digits.dropFirst()
        default: break
        }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(digits) else { return nil }
        return Dart(n, ring)
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

    /// A visit recorded as the darts that were thrown (OD-023): one to three, in order, and none
    /// after the dart that finished or bust the visit. The engine derives everything a total had to
    /// be told, so none of it can be contradicted by a client.
    case recordDarts(player: PlayerId, darts: [Dart])

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
    /// A non-zero total recorded by a player who has not opened, that no sequence beginning with a
    /// legal opening segment can make. Distinct from IMPOSSIBLE_VISIT_TOTAL because the total is
    /// perfectly possible for an opened player: 180 is three trebles, and three trebles cannot open
    /// a double-in leg.
    case IMPOSSIBLE_OPENING_TOTAL
    /// A dart that is not on the board: a treble bull, a double nought.
    case DART_INVALID
    /// A total that busts, under `BustRule.keepScoredDarts`. What stands depends on the darts before
    /// the busting one, and a total does not say — so the scorer enters the darts rather than THRØ
    /// guessing which of them came first.
    case DARTS_REQUIRED
}

public enum BustReason: String, Sendable {
    case BELOW_ZERO, REMAINDER_ONE, NOT_CHECKOUT_POSSIBLE
    /// Reached zero on a dart that may not end the leg — a treble or a single under double-out. Only
    /// darts can show it: a total of 60 from 60 reads as a checkout, and T20 from 60 is a bust.
    case NOT_A_FINISHING_DART
}

/// What one accepted visit amounted to, for the record and for every statistic built on it. Field by
/// field the Kotlin `VisitReading`; see it for what each one means.
public struct VisitReading: Equatable, Sendable {
    /// What a visit-level record carries: the darts from the opening one onward, a busting dart included.
    public let visitTotal: Int
    /// Points the visit took off the score: zero on a standard bust, the darts before the busting one
    /// under keep-scored darts.
    public let scored: Int
    public let dartsUsed: Int?
    public let dartsAtDouble: Int?
    public let bustAt: Int?
    public let darts: [Dart]?

    public init(visitTotal: Int, scored: Int, dartsUsed: Int?, dartsAtDouble: Int?,
                bustAt: Int? = nil, darts: [Dart]? = nil) {
        self.visitTotal = visitTotal
        self.scored = scored
        self.dartsUsed = dartsUsed
        self.dartsAtDouble = dartsAtDouble
        self.bustAt = bustAt
        self.darts = darts
    }
}

public enum Effect: String, Sendable { case scored, bust, leg_won, set_won, match_won }

public enum Outcome: Sendable {
    /// `reading` is nil only where an engine older than 1.4.0 produced the outcome.
    case accepted(state: MatchState, effect: Effect, bustReason: BustReason?, reading: VisitReading?)
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
    /// Who has opened in the current leg (PD-008). Under straight-in both are open from the first
    /// dart; this resets with every leg and every set, because opening is a fact about a leg.
    public var opened: [PlayerId: Bool]

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
            visitsInLeg: 0,
            opened: [home: !format.inRule.requiresOpening, away: !format.inRule.requiresOpening]
        )
    }
}
