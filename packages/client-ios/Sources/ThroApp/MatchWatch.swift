import Foundation
import SwiftUI
import ThroDesign
import ThroEngine
import ThroNet
import ThroTokens

// Following a match as it is scored (PD-044).
//
// The match stream (ADR-007) hands over a match's events in the order they committed. They are
// replayed here through the same engine the scoring phone used, into the board a watcher reads —
// what each side needs, the legs, who is throwing, and the last visit. It is this phone's reading of
// the log, for the screen: where the match stands stays the server's, and nothing here is stored.

// MARK: - what comes off the stream

/// One event off the stream, as far as a watcher needs it.
public struct WatchedEvent: Decodable, Equatable, Sendable {
    public struct Payload: Decodable, Equatable, Sendable {
        public let player: String?
        public let visitTotal: Int?
        public let dartsUsed: Int?
        public let dartsAtDouble: Int?
        public let ending: String?
        public let seat: String?
    }

    public let eventId: UUID?
    public let type: String
    public let correctsEventId: UUID?
    /// The scoring device's clock: evidence of when, never order (V002). Shown as a time, nothing more.
    public let occurredAt: String?
    public let payload: Payload

    /// An event's data, or nil for one this build cannot read — which is skipped, never guessed at.
    public static func read(_ event: StreamEvent) -> WatchedEvent? {
        try? JSONDecoder().decode(WatchedEvent.self, from: Data(event.data.utf8))
    }

    /// When it was thrown, by the thrower's phone, where that reads as an instant.
    public var thrownAt: Date? {
        guard let occurredAt else { return nil }
        for f in WatchedEvent.instants { if let d = f.date(from: occurredAt) { return d } }
        return nil
    }

    /// Postgres writes an instant with or without fractions of a second, and with an offset.
    nonisolated(unsafe) private static let instants: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [fractional, plain]
    }()
}

// MARK: - the board

/// The board a watcher reads, from their own side.
public struct WatchBoard: Equatable, Sendable {
    public struct Side: Equatable, Sendable {
        public let seat: String
        /// What they need: the score face's number.
        public let needs: Int
        public let legs: Int
        public let throwing: Bool
    }

    public struct LastVisit: Equatable, Sendable {
        public let seat: String
        public let total: Int
        public let at: Date?
    }

    public let yours: Side
    public let theirs: Side
    /// The last visit that counts: a struck one is not it.
    public let last: LastVisit?
    public let visits: Int
    public let winner: String?
    /// `retired` or `abandoned` when the match ended short.
    public let ending: String?
}

/// The events of a match, through the engine, into a board. Pure, so it is tested rather than watched.
public enum MatchReplay {
    /// The board after [events], read from [yours]'s side; nil when the format cannot be replayed — a
    /// server that did not say who threw first, or a rule this build does not know. A visit the engine
    /// refuses is still evidence; it counts for nothing here, as it did at the oche.
    public static func board(format f: MatchOnRecord.Format, yours: String, events: [WatchedEvent]) -> WatchBoard? {
        guard let first = f.throwFirst, first == "home" || first == "away",
              yours == "home" || yours == "away",
              let inRule = InRule(rawValue: f.inRule), let outRule = OutRule(rawValue: f.outRule),
              f.startingScore > 1, f.legsTarget > 0 else { return nil }
        let format = MatchFormat(startingScore: f.startingScore, inRule: inRule, outRule: outRule,
                                 legs: Structure(mode: f.legsMode == "best_of" ? .bestOf : .firstTo, target: f.legsTarget),
                                 throwFirst: PlayerId(first))
        var state = MatchState.start(format: format, home: PlayerId("home"), away: PlayerId("away"))
        // A retraction names the visit it struck by its event id, which every event now carries.
        let struck = Set(events.filter { $0.type == "VisitRetracted" }.compactMap(\.correctsEventId))
        var last: WatchBoard.LastVisit?
        var visits = 0
        var ending: String?, retired: String?
        for e in events {
            switch e.type {
            case "VisitRecorded":
                guard let id = e.eventId, !struck.contains(id),
                      let seat = e.payload.player, seat == "home" || seat == "away",
                      let total = e.payload.visitTotal else { continue }
                let visit = Command.visit(PlayerId(seat), total, dartsUsed: e.payload.dartsUsed, dartsAtDouble: e.payload.dartsAtDouble)
                if case .accepted(let next, _, _) = Engine.apply(state, visit) {
                    state = next
                    visits += 1
                    last = WatchBoard.LastVisit(seat: seat, total: total, at: e.thrownAt)
                }
            case "MatchEndedShort":
                ending = e.payload.ending
                retired = e.payload.seat
            default:
                continue
            }
        }
        func side(_ seat: String) -> WatchBoard.Side {
            let id = PlayerId(seat)
            return WatchBoard.Side(seat: seat, needs: state.remaining[id] ?? f.startingScore,
                                   legs: state.legsWonTotal[id] ?? 0, throwing: ending == nil && state.thrower == id)
        }
        let winner: String?
        switch ending {
        case "retired": winner = retired.map { $0 == "home" ? "away" : "home" }
        case "abandoned": winner = nil
        default: winner = state.winner?.value
        }
        return WatchBoard(yours: side(yours), theirs: side(yours == "home" ? "away" : "home"),
                          last: last, visits: visits, winner: winner, ending: ending)
    }
}

// MARK: - the model

/// One match, followed while its page is open.
@MainActor
public final class MatchWatchModel: ObservableObject {
    @Published public private(set) var board: WatchBoard?
    @Published public private(set) var health: StreamHealth = .connecting
    private var events: [WatchedEvent] = []
    private var seen: Set<UUID> = []

    public init() {}

    /// Follows [record] until the task running this is cancelled, which is when its page closes.
    public func follow(_ api: ThroAPI?, _ record: MatchOnRecord) async {
        guard let yours = record.yours?.seat else { return }
        board = MatchReplay.board(format: record.format, yours: yours, events: events)
        guard let api else { health = .ended("This build names no server."); return }
        for await update in await api.matchStream(record.matchId) {
            switch update {
            case .health(let h):
                health = h
            case .event(let raw):
                take(raw, format: record.format, yours: yours)
            }
        }
    }

    /// One event in, the board read again. A resend after a reconnect lands once.
    func take(_ raw: StreamEvent, format: MatchOnRecord.Format, yours: String) {
        guard let event = WatchedEvent.read(raw) else { return }
        if let id = event.eventId, !seen.insert(id).inserted { return }
        events.append(event)
        board = MatchReplay.board(format: format, yours: yours, events: events)
    }
}

// MARK: - the board on the slate

/// The board, live: what each side needs in the score face, their legs, a mark on whoever is
/// throwing, and the last visit. It says plainly when the stream is not live, because a frozen
/// number that looks live is the one thing this must never show (ADR-007).
struct LiveBoardSlate: View {
    @ObservedObject var watch: MatchWatchModel
    /// The other player as this reader may name them.
    let them: String
    let format: String

    var body: some View {
        ThroSlate(seed: 57) {
            VStack(alignment: .leading, spacing: ThroSpacing.spacing3) {
                HStack(alignment: .center, spacing: ThroSpacing.spacing2) {
                    Eyebrow(format, color: ThroColor.colorTextOnBoardSecondary)
                    Spacer(minLength: ThroSpacing.spacing2)
                    Tag(LiveBoardWords.health(watch.health, board: watch.board), tone: LiveBoardWords.tone(watch.health, board: watch.board))
                }
                if let board = watch.board {
                    VStack(spacing: ThroSpacing.spacing2) {
                        row("You", board.yours)
                        row(them, board.theirs)
                    }
                    Text(LiveBoardWords.lastLine(board, them: them))
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This match cannot be drawn here: the server did not say who threw first.")
                        .thro(ThroTypography.body)
                        .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .ended(let why) = watch.health {
                    Text(why)
                        .thro(ThroTypography.metadata)
                        .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(ThroSpacing.spacing5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ name: String, _ side: WatchBoard.Side) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ThroSpacing.spacing3) {
            // Whoever is throwing, marked the way a chalker points: a dot beside the name.
            Group {
                if side.throwing {
                    Circle().fill(ThroColor.colorTextOnBoard)
                } else {
                    Circle().strokeBorder(ThroColor.colorTextOnBoardSecondary, lineWidth: 1)
                }
            }
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
            Text(name)
                .thro(ThroTypography.heading2.weight(.bold))
                .foregroundStyle(ThroColor.colorTextOnBoard)
                .lineLimit(1)
            Text(side.legs == 1 ? "1 leg" : "\(side.legs) legs")
                .thro(ThroTypography.metadata)
                .foregroundStyle(ThroColor.colorTextOnBoardSecondary)
            Spacer(minLength: ThroSpacing.spacing2)
            Text("\(side.needs)")
                .thro(ThroTypography.display.family(.sport).weight(.bold))
                .foregroundStyle(ThroColor.colorTextOnBoard)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): needs \(side.needs), \(side.legs == 1 ? "1 leg" : "\(side.legs) legs")\(side.throwing ? ", throwing" : "")")
    }
}

/// The words on the live board. Pure, so they are tested rather than looked at.
enum LiveBoardWords {
    /// Somebody won it, or it ended short.
    static func finished(_ board: WatchBoard?) -> Bool { board?.winner != nil || board?.ending != nil }

    static func health(_ health: StreamHealth, board: WatchBoard?) -> String {
        if finished(board) { return "Finished" }
        switch health {
        case .connecting: return "Connecting"
        case .live: return "Live"
        case .stale: return "Reconnecting"
        case .ended: return "Not following"
        }
    }

    static func tone(_ health: StreamHealth, board: WatchBoard?) -> Tag.Tone {
        if board?.winner != nil || board?.ending != nil { return .neutral }
        switch health {
        case .live: return .live
        case .stale: return .warning
        case .ended: return .error
        case .connecting: return .neutral
        }
    }

    static func lastLine(_ board: WatchBoard, them: String) -> String {
        if board.ending == "abandoned" { return "Abandoned. There is no result." }
        if let winner = board.winner {
            let retired = board.ending == "retired"
            if winner == board.yours.seat { return retired ? "They retired, so it is your win." : "Your win." }
            return retired ? "You retired, so it is their win." : "Their win."
        }
        guard let last = board.last else { return "Nothing thrown yet." }
        let who = last.seat == board.yours.seat ? "You" : them
        let when = last.at.map { " at " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return "Last visit: \(who), \(last.total)\(when)."
    }
}
