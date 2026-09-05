import Foundation
import ThroEngine
import ThroJournal
import ThroStatistics

/// One match being scored on this device: the engine's state, the journal that makes it durable, and
/// the keypad's entry. This is the whole of the scoring logic; the screens only draw it.
///
/// The order inside `submit` is the durability rule from ADR-006 and is not to be rearranged:
/// the engine decides (pure, in memory) → the journal commits (fsync) → the state is applied and
/// the screen updates. If the journal throws, nothing is applied and the player is told the visit
/// was not saved — a score shown but not stored is the one thing this must never do.
public final class MatchSession: ObservableObject {
    public let journal: Journal
    public let record: MatchRecord

    @Published public private(set) var state: MatchState
    @Published public private(set) var visits: [ReplayedVisit]
    @Published public private(set) var entry: String = ""
    @Published public private(set) var prompt: Prompt?
    @Published public private(set) var notice: Notice?
    /// Set after a bust so the screen can show the restored score in the error colour until the
    /// next key is pressed.
    @Published public private(set) var bust: BustDisplay?

    public struct Notice: Equatable, Sendable {
        public enum Tone: Sendable { case neutral, success, error }
        public let text: String
        public let tone: Tone
    }

    public struct BustDisplay: Equatable, Sendable {
        public let seat: Seat
        public let restored: Int
    }

    /// PD-001's two questions, asked when they apply and never otherwise. Darts at a double is asked
    /// on every visit that BEGAN on a checkout number, finished or not; darts used only on the visit
    /// that wins the leg, the only one whose dart count is ambiguous.
    public enum Prompt: Equatable, Sendable {
        case dartsUsed(total: Int)
        case dartsAtDouble(total: Int, dartsUsed: Int?, finished: Bool)

        public var question: String {
            switch self {
            case .dartsUsed: return "Darts used to check out?"
            case .dartsAtDouble: return "Darts thrown at a double?"
            }
        }

        public var context: String {
            switch self {
            case .dartsUsed(let total): return "Finish on \(total)"
            case let .dartsAtDouble(total, _, finished): return finished ? "Finish on \(total)" : "\(total) scored from a finish"
            }
        }

        public var options: [Int] {
            switch self {
            case .dartsUsed: return [1, 2, 3]
            case let .dartsAtDouble(_, dartsUsed, finished):
                if !finished { return [0, 1, 2, 3] }
                return [1, 2, 3].filter { dartsUsed == nil || $0 <= dartsUsed! }
            }
        }

        public var preset: Int {
            switch self {
            case .dartsUsed: return 3
            case let .dartsAtDouble(_, _, finished): return finished ? 1 : 0
            }
        }
    }

    public init(journal: Journal, record: MatchRecord) throws {
        self.journal = journal
        self.record = record
        let replayed = try journal.replayVisits(record.id)
        self.state = replayed.state
        self.visits = replayed.visits
    }

    public static func start(_ new: NewMatch, in journal: Journal) throws -> MatchSession {
        try MatchSession(journal: journal, record: try journal.createMatch(new))
    }

    public static func open(_ id: MatchId, in journal: Journal) throws -> MatchSession {
        try MatchSession(journal: journal, record: try journal.match(id))
    }

    // MARK: - derived

    public var thrower: Seat? { state.thrower.flatMap(Seat.init(playerId:)) }
    public var winner: Seat? { state.winner.flatMap(Seat.init(playerId:)) }
    public var isComplete: Bool { state.isComplete }
    public func name(_ seat: Seat) -> String { record.name(seat) }
    public func remaining(_ seat: Seat) -> Int { state.remaining[seat.playerId] ?? record.startingScore }
    public func legsWon(_ seat: Seat) -> Int { state.legsWonTotal[seat.playerId] ?? 0 }
    public var checkable: Set<Int> { RuleTables.checkouts(record.outRule) }
    public var throwerOnAFinish: Bool { thrower.map { checkable.contains(remaining($0)) } ?? false }

    public var formatLabel: String {
        record.legsMode == .bestOf ? "\(record.startingScore) · Bo\(record.legsTarget)"
                                   : "\(record.startingScore) · First to \(record.legsTarget)"
    }
    public var lengthLabel: String {
        record.legsMode == .bestOf ? "Best of \(record.legsTarget)" : "First to \(record.legsTarget)"
    }
    public var outRuleLabel: String {
        switch record.outRule {
        case .double: return "Double out"
        case .master: return "Master out"
        case .straight: return "Straight out"
        }
    }

    // MARK: - keypad

    public func digit(_ d: String) {
        guard prompt == nil, !isComplete else { return }
        bust = nil
        entry = String((entry + d).prefix(3))
    }

    public func clearEntry() {
        bust = nil
        entry = ""
    }

    public func quick(_ total: Int) {
        guard prompt == nil else { return }
        bust = nil
        commit(total)
    }

    public func miss() {
        guard prompt == nil else { return }
        bust = nil
        commit(0)
    }

    public func enter() {
        guard prompt == nil, let total = Int(entry) else { return }
        bust = nil
        commit(total)
    }

    /// Answers the current prompt. `nil` is "not sure": recorded as unknown, never as zero.
    public func answer(_ value: Int?) {
        guard let current = prompt else { return }
        switch current {
        case .dartsUsed(let total):
            prompt = .dartsAtDouble(total: total, dartsUsed: value, finished: true)
        case let .dartsAtDouble(total, dartsUsed, _):
            prompt = nil
            submit(total, dartsUsed: dartsUsed, dartsAtDouble: value)
        }
    }

    /// Cancels the prompt. Nothing is submitted; the entry is kept so it can be corrected.
    public func cancelPrompt() { prompt = nil }

    // MARK: - the visit

    func commit(_ total: Int) {
        guard let seat = thrower else { return }
        let rem = remaining(seat)
        let wasOnAFinish = checkable.contains(rem)
        let finished = rem - total == 0 && wasOnAFinish
        if finished {
            prompt = .dartsUsed(total: total)
        } else if wasOnAFinish {
            prompt = .dartsAtDouble(total: total, dartsUsed: nil, finished: false)
        } else {
            submit(total, dartsUsed: nil, dartsAtDouble: nil)
        }
    }

    func submit(_ total: Int, dartsUsed: Int?, dartsAtDouble: Int?) {
        guard let seat = thrower else { return }
        let before = remaining(seat)
        let leg = state.currentLeg
        let command = Command.visit(seat.playerId, total, dartsUsed: dartsUsed, dartsAtDouble: dartsAtDouble)

        switch Engine.apply(state, command) {
        case .rejected(let reason):
            // The entry stays on screen so the player can see what was refused and fix it.
            notice = Notice(text: Copy.rejected(reason, total: total), tone: .error)

        case let .accepted(next, effect, bustReason):
            do {
                try journal.append(command, to: record.id)   // flush …
            } catch {
                notice = Notice(text: Copy.notSaved(error), tone: .error)
                return                                        // … or nothing happened
            }
            let ordinal = visits.filter { $0.seat == seat && $0.legOrdinal == leg }.count + 1
            let won = effect == .leg_won || effect == .set_won || effect == .match_won
            visits.append(ReplayedVisit(
                seat: seat, legOrdinal: leg, visitOrdinal: ordinal,
                visitTotal: total, dartsUsed: dartsUsed, dartsAtDouble: dartsAtDouble,
                remainingBefore: before,
                remainingAfter: won ? 0 : (next.remaining[seat.playerId] ?? before),
                bust: effect == .bust, wonLeg: won
            ))
            state = next                                      // … then apply
            entry = ""

            let nextName = thrower.map(name) ?? ""
            switch effect {
            case .bust:
                bust = BustDisplay(seat: seat, restored: before)
                notice = Notice(text: Copy.bust(bustReason, total: total, restored: before, next: nextName), tone: .error)
            case .leg_won, .set_won:
                notice = Notice(text: Copy.legWon(leg: leg, by: name(seat), next: nextName), tone: .success)
            case .scored, .match_won:
                notice = nil
            }
        }
    }

    // MARK: - statistics

    /// The six figures the result screen shows, for one seat, each honest about its basis.
    public func statistics(for seat: Seat) -> [StatLine] {
        let records = visits.filter { $0.seat == seat }.map {
            VisitRecord(legOrdinal: $0.legOrdinal, visitOrdinal: $0.visitOrdinal, visitTotal: $0.visitTotal,
                        dartsUsed: $0.dartsUsed, bust: $0.bust, remainingBefore: $0.remainingBefore,
                        remainingAfter: $0.remainingAfter, wonLeg: $0.wonLeg, dartsAtDouble: $0.dartsAtDouble)
        }
        return [
            StatPresentation.line("3-dart average", Statistics.threeDartAverage(records), kind: .average),
            StatPresentation.line("First 9", Statistics.firstNineAverage(records), kind: .average),
            StatPresentation.line("Checkout %", Statistics.checkoutPercentage(records, checkable: checkable), kind: .percent),
            StatPresentation.line("180s", Statistics.maximums(records), kind: .count),
            StatPresentation.line("Highest checkout", Statistics.highestCheckout(records), kind: .count),
            StatPresentation.line("140+", Statistics.scoresAtLeast(records, threshold: 140), kind: .count),
        ]
    }
}

/// A statistic as text. EXACT is a number; BOUNDED is a range and says so; UNAVAILABLE is a dash
/// and says why. A bounded figure is never collapsed to a point value.
public struct StatLine: Identifiable, Equatable, Sendable {
    public let label: String
    public let value: String
    public let note: String?
    public var id: String { label }
}

public enum StatPresentation {
    public enum Kind: Sendable { case average, percent, count }

    public static func line(_ label: String, _ stat: Stat, kind: Kind) -> StatLine {
        switch stat.basis {
        case .exact:
            // Exact can still carry a disclosure — a first nine that excludes legs ended before nine darts.
            return StatLine(label: label, value: format(stat.value ?? 0, kind), note: stat.note)
        case .bounded:
            let lower = format(stat.lower ?? 0, kind), upper = format(stat.upper ?? 0, kind)
            return StatLine(label: label, value: "\(lower)–\(upper)",
                            note: stat.note ?? "Range — the exact figure is not known")
        case .unavailable:
            return StatLine(label: label, value: "—", note: stat.note ?? "Not available")
        }
    }

    static func format(_ v: Double, _ kind: Kind) -> String {
        switch kind {
        case .average: return String(format: "%.1f", v)
        case .percent: return String(format: "%.0f%%", v)
        case .count: return String(format: "%.0f", v)
        }
    }
}

/// The words on screen. The rejection and bust texts are the harness's (services/api scorer.html),
/// with the design's Snackbar form for a bust — "Bust. Score restored to 186. Wilson to throw." —
/// carrying the reason when the engine gives one.
public enum Copy {
    public static func rejected(_ reason: RejectionReason, total: Int) -> String {
        switch reason {
        case .IMPOSSIBLE_VISIT_TOTAL: return "\(total) cannot be scored with three darts."
        case .VISIT_TOTAL_OUT_OF_RANGE: return "A visit cannot exceed 180."
        case .NOT_YOUR_TURN: return "It is not that player's turn."
        case .MATCH_COMPLETE: return "The match is already complete."
        case .DARTS_USED_INVALID: return "Only a leg-winning visit can use fewer than three darts."
        case .DARTS_AT_DOUBLE_INVALID: return "That number of darts at a double is not possible from this score."
        }
    }

    public static func bust(_ reason: BustReason?, total: Int, restored: Int, next: String) -> String {
        let why: String
        switch reason {
        case .REMAINDER_ONE: why = "Bust — that leaves 1."
        case .NOT_CHECKOUT_POSSIBLE: why = "Bust — \(total) cannot be finished on a double."
        case .BELOW_ZERO, .none: why = "Bust."
        }
        return "\(why) Score restored to \(restored). \(next) to throw."
    }

    public static func legWon(leg: Int, by winner: String, next: String) -> String {
        "Leg \(leg) to \(winner). \(next) to throw."
    }

    public static func notSaved(_ error: Error) -> String {
        "Not saved, so not scored. \(error)"
    }
}
