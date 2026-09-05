import Foundation
import SQLite3
import ThroEngine

// ADR-006's on-device journal.
//
// The durability rule is non-negotiable: the command is flushed to the journal BEFORE it is applied
// and acknowledged. So the order of operations for one visit is: the engine — pure, in memory —
// says whether the command is valid; if it is, this journal commits it under the configuration
// ADR-006 measured; only then does the screen update. Rendering first and persisting second loses
// a dart on any crash between, and the player notices when the scores disagree with the board.
//
// This module reaches the engine and SQLite and nothing else. LATENCY_BUDGETS.md makes the
// network-independence of scoring a structural requirement, and the module graph is where it is
// enforced: there is no network module here for this to depend on.

public enum JournalError: Error, Equatable, CustomStringConvertible {
    case sqlite(String)
    /// A pragma was requested and the database reports something else. `PRAGMA journal_mode = WAL`
    /// does not fail when it cannot switch — it returns a row naming the mode actually in force —
    /// so a configuration that is not read back is a configuration that is assumed.
    case configurationNotInForce(pragma: String, wanted: String, got: String)
    case matchNotFound(String)
    /// The journal holds a command the engine rejects on replay. That is corruption, and a replay
    /// that shrugged past it would rebuild a match that never happened.
    case replayRejected(seq: Int64, reason: String)

    public var description: String {
        switch self {
        case .sqlite(let m): return "SQLite: \(m)"
        case let .configurationNotInForce(p, w, g):
            return "PRAGMA \(p) requested \(w) but the database reports \(g); the measured configuration is not in force"
        case .matchNotFound(let id): return "no match \(id) in this journal"
        case let .replayRejected(seq, reason): return "journal entry \(seq) rejected on replay: \(reason)"
        }
    }
}

/// The one durability configuration ADR-006 measured and chose — WAL, `synchronous=FULL`, and the
/// two Apple barriers that plain fsync does not provide. Stated once, verified in force on every
/// open, never assumed.
public struct DurabilityConfiguration: Equatable, Sendable {
    public let journalMode: String
    public let synchronous: String
    public let fullFsync: Bool
    public let checkpointFullFsync: Bool

    public init(journalMode: String, synchronous: String, fullFsync: Bool, checkpointFullFsync: Bool) {
        self.journalMode = journalMode
        self.synchronous = synchronous
        self.fullFsync = fullFsync
        self.checkpointFullFsync = checkpointFullFsync
    }

    /// iPhone15,3 / iOS 26.1: P95 1.64 ms against a 20 ms budget. See ADR-006, "Measurement status".
    public static let measured = DurabilityConfiguration(
        journalMode: "WAL", synchronous: "FULL", fullFsync: true, checkpointFullFsync: true
    )
}

public struct DeviceId: Hashable, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

public struct MatchId: Hashable, Sendable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

/// Which competitor. Display names are presentation; the engine's PlayerIds are these two strings
/// for every local match, so a journal row never depends on how a name was spelled.
public enum Seat: String, CaseIterable, Sendable {
    case home, away

    public var playerId: PlayerId { PlayerId(rawValue) }
    public init?(playerId: PlayerId) { self.init(rawValue: playerId.value) }
    public var opponent: Seat { self == .home ? .away : .home }
}

/// What is needed to start a local match. Straight in; the out-rule and structure are the
/// player's choice at match-ready.
public struct NewMatch: Sendable {
    public let homeName: String
    public let awayName: String
    public let startingScore: Int
    public let outRule: OutRule
    public let legsMode: StructureMode
    public let legsTarget: Int
    public let throwFirst: Seat

    public init(homeName: String, awayName: String, startingScore: Int = 501, outRule: OutRule = .double,
                legsMode: StructureMode = .bestOf, legsTarget: Int = 5, throwFirst: Seat = .home) {
        self.homeName = homeName
        self.awayName = awayName
        self.startingScore = startingScore
        self.outRule = outRule
        self.legsMode = legsMode
        self.legsTarget = legsTarget
        self.throwFirst = throwFirst
    }
}

public struct MatchRecord: Equatable, Sendable {
    public let id: MatchId
    public let homeName: String
    public let awayName: String
    public let startingScore: Int
    public let outRule: OutRule
    public let legsMode: StructureMode
    public let legsTarget: Int
    public let throwFirst: Seat
    public let startedAt: Date

    public var format: MatchFormat {
        MatchFormat(startingScore: startingScore, inRule: .straight, outRule: outRule,
                    legs: Structure(mode: legsMode, target: legsTarget), throwFirst: throwFirst.playerId)
    }

    public var initialState: MatchState {
        MatchState.start(format: format, home: Seat.home.playerId, away: Seat.away.playerId)
    }

    public func name(_ seat: Seat) -> String { seat == .home ? homeName : awayName }
}

/// One committed command.
public struct JournalEntry: Equatable, Sendable {
    public let matchId: MatchId
    public let deviceId: DeviceId
    public let deviceSeq: Int64
    public let commandId: String
    public let seat: Seat
    public let visitTotal: Int
    public let dartsUsed: Int?
    public let dartsAtDouble: Int?
    public let occurredAt: Date

    public var command: Command {
        .recordVisit(player: seat.playerId, visitTotal: visitTotal, dartsUsed: dartsUsed, dartsAtDouble: dartsAtDouble)
    }
}

/// One visit as the engine saw it, produced by replay. Carries what the statistics need and what
/// the journal row alone cannot say: the remaining before and after, whether it bust, whether it
/// won the leg, and the visit's ordinal within the leg FOR THAT SEAT — per (player, leg), never
/// shared across the two competitors, which is the mistake that once put the wrong three visits
/// into a first-nine average.
public struct ReplayedVisit: Equatable, Sendable {
    public let seat: Seat
    public let legOrdinal: Int
    public let visitOrdinal: Int
    public let visitTotal: Int
    public let dartsUsed: Int?
    public let dartsAtDouble: Int?
    public let remainingBefore: Int
    public let remainingAfter: Int
    public let bust: Bool
    public let wonLeg: Bool

    public init(seat: Seat, legOrdinal: Int, visitOrdinal: Int, visitTotal: Int, dartsUsed: Int?, dartsAtDouble: Int?,
                remainingBefore: Int, remainingAfter: Int, bust: Bool, wonLeg: Bool) {
        self.seat = seat
        self.legOrdinal = legOrdinal
        self.visitOrdinal = visitOrdinal
        self.visitTotal = visitTotal
        self.dartsUsed = dartsUsed
        self.dartsAtDouble = dartsAtDouble
        self.remainingBefore = remainingBefore
        self.remainingAfter = remainingAfter
        self.bust = bust
        self.wonLeg = wonLeg
    }
}

public final class Journal {
    private let handle: OpaquePointer
    public let deviceId: DeviceId
    public let configuration: DurabilityConfiguration

    /// Opens (creating if needed) the journal at `path` and verifies the configuration is in force.
    public init(path: String, deviceId: DeviceId, configuration: DurabilityConfiguration = .measured) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let h = db else {
            if let leaked = db { sqlite3_close(leaked) }
            throw JournalError.sqlite("could not open \(path)")
        }
        handle = h
        self.deviceId = deviceId
        self.configuration = configuration
        // If either throws, Swift still runs deinit for a fully initialised class instance, which
        // closes the handle — closing it here as well would close it twice.
        try Journal.configure(h, configuration)
        try Journal.migrate(h)
    }

    deinit { sqlite3_close(handle) }

    // MARK: - configuration

    static func configure(_ h: OpaquePointer, _ c: DurabilityConfiguration) throws {
        // Order matters: fullfsync must be set before the journal-mode change that fsyncs.
        try exec(h, "PRAGMA fullfsync = \(c.fullFsync ? 1 : 0);")
        try exec(h, "PRAGMA checkpoint_fullfsync = \(c.checkpointFullFsync ? 1 : 0);")
        try exec(h, "PRAGMA journal_mode = \(c.journalMode);")
        try exec(h, "PRAGMA synchronous = \(c.synchronous);")
        try exec(h, "PRAGMA foreign_keys = ON;")
        try verifyInForce(h, c)
    }

    static func verifyInForce(_ h: OpaquePointer, _ c: DurabilityConfiguration) throws {
        // PRAGMA synchronous reads back as a number: OFF 0, NORMAL 1, FULL 2, EXTRA 3.
        let synchronous = ["OFF": "0", "NORMAL": "1", "FULL": "2", "EXTRA": "3"]
        let expected: [(String, String)] = [
            ("journal_mode", c.journalMode.lowercased()),
            ("synchronous", synchronous[c.synchronous.uppercased()] ?? c.synchronous),
            ("fullfsync", c.fullFsync ? "1" : "0"),
            ("checkpoint_fullfsync", c.checkpointFullFsync ? "1" : "0"),
        ]
        for (name, want) in expected {
            let got = pragmaValue(h, name)?.lowercased() ?? "(no value)"
            guard got == want else {
                throw JournalError.configurationNotInForce(pragma: name, wanted: want, got: got)
            }
        }
    }

    /// What the database reports for each of the four durability pragmas, right now.
    public var configurationInForce: [String: String] {
        var out: [String: String] = [:]
        for name in ["journal_mode", "synchronous", "fullfsync", "checkpoint_fullfsync"] {
            out[name] = Journal.pragmaValue(handle, name) ?? "(no value)"
        }
        return out
    }

    static func pragmaValue(_ h: OpaquePointer, _ name: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, "PRAGMA \(name);", -1, &stmt, nil) == SQLITE_OK, let s = stmt else { return nil }
        defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW, let text = sqlite3_column_text(s, 0) else { return nil }
        return String(cString: text)
    }

    // MARK: - schema

    static func migrate(_ h: OpaquePointer) throws {
        try exec(h, """
            CREATE TABLE IF NOT EXISTS local_match (
              match_id       TEXT PRIMARY KEY,
              home_name      TEXT NOT NULL,
              away_name      TEXT NOT NULL,
              starting_score INTEGER NOT NULL,
              out_rule       TEXT NOT NULL,
              legs_mode      TEXT NOT NULL,
              legs_target    INTEGER NOT NULL,
              throw_first    TEXT NOT NULL,
              started_at     TEXT NOT NULL,
              device_id      TEXT NOT NULL
            );
            """)
        try exec(h, """
            CREATE TABLE IF NOT EXISTS journal (
              match_id        TEXT NOT NULL REFERENCES local_match(match_id),
              device_id       TEXT NOT NULL,
              device_seq      INTEGER NOT NULL,
              command_id      TEXT NOT NULL UNIQUE,
              seat            TEXT NOT NULL,
              visit_total     INTEGER NOT NULL,
              darts_used      INTEGER,
              darts_at_double INTEGER,
              occurred_at     TEXT NOT NULL,
              PRIMARY KEY (match_id, device_id, device_seq)
            );
            """)
        // Append-only, enforced by the database rather than by discipline — the same property the
        // server's grants give evidence.event. Corrections, when they come, are new events.
        try exec(h, """
            CREATE TRIGGER IF NOT EXISTS journal_append_only_update BEFORE UPDATE ON journal
            BEGIN SELECT RAISE(ABORT, 'journal is append-only'); END;
            """)
        try exec(h, """
            CREATE TRIGGER IF NOT EXISTS journal_append_only_delete BEFORE DELETE ON journal
            BEGIN SELECT RAISE(ABORT, 'journal is append-only'); END;
            """)
    }

    // MARK: - matches

    @discardableResult
    public func createMatch(_ m: NewMatch, id: MatchId = MatchId(UUID().uuidString), startedAt: Date = Date()) throws -> MatchRecord {
        try run("""
            INSERT INTO local_match (match_id, home_name, away_name, starting_score, out_rule, legs_mode, legs_target,
                               throw_first, started_at, device_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, [
                .text(id.value), .text(m.homeName), .text(m.awayName), .int(Int64(m.startingScore)),
                .text(m.outRule.rawValue), .text(m.legsMode == .bestOf ? "bestOf" : "firstTo"),
                .int(Int64(m.legsTarget)), .text(m.throwFirst.rawValue),
                .text(Journal.iso.string(from: startedAt)), .text(deviceId.value),
            ])
        return try match(id)
    }

    public func match(_ id: MatchId) throws -> MatchRecord {
        var found: MatchRecord?
        try run("SELECT * FROM local_match WHERE match_id = ?;", [.text(id.value)]) { s in
            found = Journal.record(from: s)
        }
        guard let found else { throw JournalError.matchNotFound(id.value) }
        return found
    }

    /// Every match on this device, newest first.
    public func matches() throws -> [MatchRecord] {
        var out: [MatchRecord] = []
        try run("SELECT * FROM local_match ORDER BY started_at DESC, rowid DESC;", []) { s in
            out.append(Journal.record(from: s))
        }
        return out
    }

    private static func record(from s: OpaquePointer) -> MatchRecord {
        MatchRecord(
            id: MatchId(text(s, 0)),
            homeName: text(s, 1),
            awayName: text(s, 2),
            startingScore: Int(sqlite3_column_int64(s, 3)),
            outRule: OutRule(rawValue: text(s, 4)) ?? .double,
            legsMode: text(s, 5) == "firstTo" ? .firstTo : .bestOf,
            legsTarget: Int(sqlite3_column_int64(s, 6)),
            throwFirst: Seat(rawValue: text(s, 7)) ?? .home,
            startedAt: iso.date(from: text(s, 8)) ?? Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - the journal

    /// Appends one command the engine has already accepted. Returns only after the transaction has
    /// committed under the measured configuration — that is the durability rule, and it is why the
    /// screen must not update until this returns.
    @discardableResult
    public func append(_ command: Command, to matchId: MatchId,
                       occurredAt: Date = Date(), commandId: String = UUID().uuidString) throws -> JournalEntry {
        guard case let .recordVisit(player, visitTotal, dartsUsed, dartsAtDouble) = command else {
            throw JournalError.sqlite("unsupported command")
        }
        guard let seat = Seat(playerId: player) else {
            throw JournalError.sqlite("player \(player.value) is not a seat in a local match")
        }

        try Journal.exec(handle, "BEGIN IMMEDIATE;")
        do {
            var next: Int64 = 1
            try run("SELECT COALESCE(MAX(device_seq), 0) + 1 FROM journal WHERE match_id = ? AND device_id = ?;",
                    [.text(matchId.value), .text(deviceId.value)]) { s in
                next = sqlite3_column_int64(s, 0)
            }
            try run("""
                INSERT INTO journal (match_id, device_id, device_seq, command_id, seat, visit_total,
                                     darts_used, darts_at_double, occurred_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """, [
                    .text(matchId.value), .text(deviceId.value), .int(next), .text(commandId),
                    .text(seat.rawValue), .int(Int64(visitTotal)),
                    dartsUsed.map { Param.int(Int64($0)) } ?? Param.null,
                    dartsAtDouble.map { Param.int(Int64($0)) } ?? Param.null,
                    .text(Journal.iso.string(from: occurredAt)),
                ])
            // COMMIT is where the barrier happens.
            try Journal.exec(handle, "COMMIT;")
            return JournalEntry(matchId: matchId, deviceId: deviceId, deviceSeq: next, commandId: commandId,
                                seat: seat, visitTotal: visitTotal, dartsUsed: dartsUsed,
                                dartsAtDouble: dartsAtDouble, occurredAt: occurredAt)
        } catch {
            try? Journal.exec(handle, "ROLLBACK;")
            throw error
        }
    }

    /// Every committed command for a match, in the order it was committed on this device.
    public func entries(for matchId: MatchId) throws -> [JournalEntry] {
        var out: [JournalEntry] = []
        try run("""
            SELECT match_id, device_id, device_seq, command_id, seat, visit_total, darts_used, darts_at_double, occurred_at
            FROM journal WHERE match_id = ? ORDER BY rowid;
            """, [.text(matchId.value)]) { s in
            out.append(JournalEntry(
                matchId: MatchId(Journal.text(s, 0)),
                deviceId: DeviceId(Journal.text(s, 1)),
                deviceSeq: sqlite3_column_int64(s, 2),
                commandId: Journal.text(s, 3),
                seat: Seat(rawValue: Journal.text(s, 4)) ?? .home,
                visitTotal: Int(sqlite3_column_int64(s, 5)),
                dartsUsed: Journal.optionalInt(s, 6),
                dartsAtDouble: Journal.optionalInt(s, 7),
                occurredAt: Journal.iso.date(from: Journal.text(s, 8)) ?? Date(timeIntervalSince1970: 0)
            ))
        }
        return out
    }

    /// Folds the journal through the engine and returns the state it rebuilds. A rejection during
    /// replay is corruption and is thrown, never skipped.
    public func replay(_ id: MatchId) throws -> MatchState {
        try replayVisits(id).state
    }

    /// Replay that also yields each visit as the engine saw it, for the statistics layer.
    public func replayVisits(_ id: MatchId) throws -> (state: MatchState, visits: [ReplayedVisit]) {
        let record = try match(id)
        var state = record.initialState
        var visits: [ReplayedVisit] = []
        var ordinal: [Seat: [Int: Int]] = [.home: [:], .away: [:]]   // seat -> leg -> visits so far

        for e in try entries(for: id) {
            let leg = state.currentLeg
            let before = state.remaining[e.seat.playerId] ?? 0
            switch Engine.apply(state, e.command) {
            case let .accepted(next, effect, _):
                let n = (ordinal[e.seat]?[leg] ?? 0) + 1
                ordinal[e.seat]?[leg] = n
                let won = effect == .leg_won || effect == .set_won || effect == .match_won
                visits.append(ReplayedVisit(
                    seat: e.seat, legOrdinal: leg, visitOrdinal: n,
                    visitTotal: e.visitTotal, dartsUsed: e.dartsUsed, dartsAtDouble: e.dartsAtDouble,
                    remainingBefore: before,
                    remainingAfter: won ? 0 : (next.remaining[e.seat.playerId] ?? before),
                    bust: effect == .bust, wonLeg: won
                ))
                state = next
            case let .rejected(reason):
                throw JournalError.replayRejected(seq: e.deviceSeq, reason: reason.rawValue)
            }
        }
        return (state, visits)
    }

    // MARK: - plumbing

    enum Param { case text(String), int(Int64), null }

    /// Runs one statement. Text parameters are bound SQLITE_STATIC against buffers this function
    /// owns until the statement is finalised — never a bridged Swift String, whose buffer lives for
    /// one call, and never a bit-cast SQLITE_TRANSIENT, which is undefined behaviour and was a
    /// suspected crash in the durability probe.
    func run(_ sql: String, _ params: [Param], row: ((OpaquePointer) -> Void)? = nil) throws {
        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }           // declared first, so it runs after finalize

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            throw JournalError.sqlite("prepare failed: \(String(cString: sqlite3_errmsg(handle)))")
        }
        defer { sqlite3_finalize(s) }

        for (i, p) in params.enumerated() {
            let index = Int32(i + 1)
            switch p {
            case .text(let value):
                guard let c = strdup(value) else { throw JournalError.sqlite("strdup failed") }
                owned.append(c)
                sqlite3_bind_text(s, index, c, -1, nil)
            case .int(let value):
                sqlite3_bind_int64(s, index, value)
            case .null:
                sqlite3_bind_null(s, index)
            }
        }

        while true {
            let rc = sqlite3_step(s)
            if rc == SQLITE_ROW { row?(s); continue }
            if rc == SQLITE_DONE { return }
            throw JournalError.sqlite("\(sql.prefix(60))…: \(String(cString: sqlite3_errmsg(handle)))")
        }
    }

    /// For tests: run arbitrary SQL against this journal's own connection.
    func exec(_ sql: String) throws { try Journal.exec(handle, sql) }

    static func exec(_ h: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(h, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw JournalError.sqlite("\(sql.prefix(60))…: \(message)")
        }
    }

    static func text(_ s: OpaquePointer, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(s, i) else { return "" }
        return String(cString: c)
    }

    static func optionalInt(_ s: OpaquePointer, _ i: Int32) -> Int? {
        sqlite3_column_type(s, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s, i))
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
