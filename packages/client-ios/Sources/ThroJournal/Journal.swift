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
    /// An undo was asked for and there is no standing visit to strike.
    case nothingToRetract
    /// The journal holds a command the engine rejects on replay. That is corruption, and a replay
    /// that shrugged past it would rebuild a match that never happened.
    case replayRejected(seq: Int64, reason: String)
    /// Something was written to a match that has already been retired or abandoned (PD-016). An
    /// ending is final, so this refuses rather than appending after it.
    case alreadyEnded(Ending)

    public var description: String {
        switch self {
        case .sqlite(let m): return "SQLite: \(m)"
        case let .configurationNotInForce(p, w, g):
            return "PRAGMA \(p) requested \(w) but the database reports \(g); the measured configuration is not in force"
        case .matchNotFound(let id): return "no match \(id) in this journal"
        case .nothingToRetract: return "there is no visit to undo"
        case let .replayRejected(seq, reason): return "journal entry \(seq) rejected on replay: \(reason)"
        case let .alreadyEnded(e):
            switch e {
            case .retired: return "this match was already retired, and an ending is final"
            case .abandoned: return "this match was already abandoned, and an ending is final"
            }
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
/// Somebody who plays on this device (ADR-016, PD-012).
///
/// The name on a match row is what was typed and what is displayed; this is who it was. The
/// difference matters exactly once, and it matters a great deal then: when accounts arrive, a claim
/// is a mapping from one of these to an account, and every match that person appears in comes with
/// it. Free text cannot be claimed — "Jenson", "jenson" and "Jenson L" are three strings and one
/// player, and a claim that had to guess would either lose matches or steal them.
public struct LocalPerson: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

public struct NewMatch: Sendable {
    public let homeName: String
    public let awayName: String
    public let startingScore: Int
    public let inRule: InRule
    public let outRule: OutRule
    public let legsMode: StructureMode
    public let legsTarget: Int
    public let throwFirst: Seat
    /// Who each name refers to, when the device knows (ADR-016). Nil is normal and always readable:
    /// a match without them is a match that cannot be claimed until its players are named.
    public let homePlayerId: String?
    public let awayPlayerId: String?

    public init(homeName: String, awayName: String, startingScore: Int = 501, inRule: InRule = .straight,
                outRule: OutRule = .double, legsMode: StructureMode = .bestOf, legsTarget: Int = 5,
                throwFirst: Seat = .home, homePlayerId: String? = nil, awayPlayerId: String? = nil) {
        self.homePlayerId = homePlayerId
        self.awayPlayerId = awayPlayerId
        self.homeName = homeName
        self.awayName = awayName
        self.startingScore = startingScore
        self.inRule = inRule
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
    public let inRule: InRule
    public let outRule: OutRule
    public let legsMode: StructureMode
    public let legsTarget: Int
    public let throwFirst: Seat
    public let startedAt: Date
    /// Who each name refers to, when the device knows (ADR-016).
    public let homePlayerId: String?
    public let awayPlayerId: String?

    public func playerId(_ seat: Seat) -> String? { seat == .home ? homePlayerId : awayPlayerId }

    public var format: MatchFormat {
        MatchFormat(startingScore: startingScore, inRule: inRule, outRule: outRule,
                    legs: Structure(mode: legsMode, target: legsTarget), throwFirst: throwFirst.playerId)
    }

    public var initialState: MatchState {
        MatchState.start(format: format, home: Seat.home.playerId, away: Seat.away.playerId)
    }

    public func name(_ seat: Seat) -> String { seat == .home ? homeName : awayName }
}

/// One committed row: a visit, or a retraction that strikes an earlier visit from the effective
/// record. The shape is the server's (`AccountedVisit.correctsSeq`): a correction supersedes, it never
/// deletes, and the struck row stays for an investigator to read. PD-004.
public struct JournalEntry: Equatable, Sendable {
    /// What a row is.
    ///
    /// `unknown` is not written by anything; it is what a row written by a LATER build reads back
    /// as. It exists because the alternative — the one this journal shipped with — was to fall back
    /// to `visit`, which would have replayed somebody else's confirmation as a nil-scoring visit and
    /// quietly changed the score and every statistic derived from it. Replay throws on it instead.
    public enum Kind: String, Sendable {
        case visit, retraction, confirmation, contest, retirement, abandonment, unknown

        /// The kinds that carry a score. Everything else is a fact about the record, not a throw.
        var isScoring: Bool { self == .visit }

        /// The kinds that close a match short of its format (PD-016). Both are final.
        var endsTheMatch: Bool { self == .retirement || self == .abandonment }

        /// The kinds that change what the result IS, and so make an earlier agreement stale.
        /// A confirmation or a contest is somebody's opinion of the result and changes nothing.
        var changesTheResult: Bool { isScoring || self == .retraction || endsTheMatch }
    }

    public let matchId: MatchId
    public let deviceId: DeviceId
    public let deviceSeq: Int64
    public let commandId: String
    public let kind: Kind
    public let seat: Seat
    public let visitTotal: Int
    public let dartsUsed: Int?
    public let dartsAtDouble: Int?
    /// For a retraction: the `deviceSeq` of the visit it strikes.
    public let correctsSeq: Int64?
    public let occurredAt: Date

    /// The engine command a visit carries. Nothing else carries one; replay skips them.
    public var command: Command? {
        guard kind.isScoring else { return nil }
        return .recordVisit(player: seat.playerId, visitTotal: visitTotal, dartsUsed: dartsUsed, dartsAtDouble: dartsAtDouble)
    }
}

/// How a match ended short of its format (PD-016).
///
/// The founder chose to have both, and they are genuinely different things rather than two words
/// for one. A **retirement** is a concession: somebody stops and the other player wins, which is
/// how darts has always handled an injury or a walk-off, and it is a result that should count. An
/// **abandonment** has no winner — the pub shut, the lights went out — and inventing one would put a
/// win on somebody's record that nobody threw for.
///
/// Collapsing them would force exactly one of those two errors, which is why there are two.
public enum Ending: Equatable, Sendable {
    /// `seat` is the player who **retired**. The other seat won.
    case retired(by: Seat)
    /// Nobody won, and nobody is going to be given the win.
    case abandoned

    /// Who won, when anybody did. `nil` for an abandonment is the whole point of the type.
    public var winner: Seat? {
        switch self {
        case let .retired(by): return by == .home ? .away : .home
        case .abandoned: return nil
        }
    }

    /// Whether this ending produces a result at all. An abandoned match is a thing that happened,
    /// not a match somebody won, so nothing downstream may treat it as one.
    public var isResult: Bool { winner != nil }

    var kind: JournalEntry.Kind {
        switch self {
        case .retired: return .retirement
        case .abandoned: return .abandonment
        }
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
    /// The identity every row in this journal is written under.
    ///
    /// It belongs to the journal, not to the caller. The first open writes the identity it was given;
    /// every open after that reads back the one already there and uses it, whatever it was passed.
    /// The caller's copy used to live in `UserDefaults`, which can be lost while the journal file
    /// survives — a restore that brings back Application Support but not the preferences, say. A new
    /// identity would restart `device_seq` at 1 for a match that already had rows, and ADR-006's
    /// gapless per-device sequence is what the server uses to notice a device is missing events. One
    /// device would arrive at the server as two, each with its own sequence, and neither with a gap
    /// to report.
    public private(set) var deviceId: DeviceId
    /// The identity the caller asked for, when the journal already had a different one. Nothing is
    /// rewritten and nothing is refused — the rows are still this device's rows — but the disagreement
    /// is a fact about this install and is not swallowed.
    public private(set) var deviceIdSupersededCallers: DeviceId?
    public let configuration: DurabilityConfiguration

    /// Opens (creating if needed) the journal at `path` and verifies the configuration is in force.
    public init(path: String, deviceId: DeviceId, configuration: DurabilityConfiguration = .measured) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let h = db else {
            if let leaked = db { sqlite3_close(leaked) }
            throw JournalError.sqlite("could not open \(path)")
        }
        handle = h
        self.configuration = configuration
        // If any of these throws, Swift still runs deinit for a fully initialised class instance,
        // which closes the handle — closing it here as well would close it twice. `deviceId` is
        // assigned before they run for the same reason.
        self.deviceId = deviceId
        self.deviceIdSupersededCallers = nil
        try Journal.configure(h, configuration)
        try Journal.migrate(h)
        let settled = try Journal.settleDeviceId(h, asked: deviceId)
        self.deviceId = settled.inForce
        self.deviceIdSupersededCallers = settled.superseded
    }

    /// The journal's own identity, written once and read back for ever after.
    static func settleDeviceId(
        _ h: OpaquePointer, asked: DeviceId,
    ) throws -> (inForce: DeviceId, superseded: DeviceId?) {
        var existing: String?
        var read: OpaquePointer?
        guard sqlite3_prepare_v2(h, "SELECT value FROM meta WHERE key = 'device_id';", -1, &read, nil) == SQLITE_OK,
              let r = read else {
            throw JournalError.sqlite("could not read the journal's device identity")
        }
        defer { sqlite3_finalize(r) }
        if sqlite3_step(r) == SQLITE_ROW, let c = sqlite3_column_text(r, 0) { existing = String(cString: c) }

        guard let existing else {
            var write: OpaquePointer?
            guard sqlite3_prepare_v2(h, "INSERT INTO meta (key, value) VALUES ('device_id', ?);", -1, &write, nil) == SQLITE_OK,
                  let w = write else {
                throw JournalError.sqlite("could not write the journal's device identity")
            }
            defer { sqlite3_finalize(w) }
            // Bound against a buffer this function owns until the statement is finalised, as `run`
            // does and for the same reason: a bridged Swift String's buffer lives for one call.
            guard let owned = strdup(asked.value) else { throw JournalError.sqlite("strdup failed") }
            defer { free(owned) }
            sqlite3_bind_text(w, 1, owned, -1, nil)
            guard sqlite3_step(w) == SQLITE_DONE else {
                throw JournalError.sqlite("could not write the journal's device identity: \(String(cString: sqlite3_errmsg(h)))")
            }
            return (asked, nil)
        }
        return (DeviceId(existing), existing == asked.value ? nil : asked)
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

    static func columnNames(_ h: OpaquePointer, table: String) throws -> Set<String> {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK, let st = stmt else {
            throw JournalError.sqlite("could not read the columns of \(table)")
        }
        defer { sqlite3_finalize(st) }
        var names = Set<String>()
        while sqlite3_step(st) == SQLITE_ROW {
            if let c = sqlite3_column_text(st, 1) { names.insert(String(cString: c)) }
        }
        return names
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
              device_id      TEXT NOT NULL,
              in_rule        TEXT NOT NULL DEFAULT 'straight'
            );
            """)
        // The journal's own facts about itself. Small on purpose: the only thing in it is the
        // identity every row is written under, which must not live anywhere the journal file can
        // outlive.
        try exec(h, """
            CREATE TABLE IF NOT EXISTS meta (
              key   TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            """)
        try exec(h, """
            CREATE TABLE IF NOT EXISTS journal (
              match_id        TEXT NOT NULL REFERENCES local_match(match_id),
              device_id       TEXT NOT NULL,
              device_seq      INTEGER NOT NULL,
              command_id      TEXT NOT NULL UNIQUE,
              kind            TEXT NOT NULL DEFAULT 'visit',
              seat            TEXT NOT NULL,
              visit_total     INTEGER NOT NULL,
              darts_used      INTEGER,
              darts_at_double INTEGER,
              corrects_seq    INTEGER,
              occurred_at     TEXT NOT NULL,
              PRIMARY KEY (match_id, device_id, device_seq)
            );
            """)
        // Journals written before corrections existed lack two columns. ADD COLUMN is the one schema
        // change SQLite makes without rewriting a row, so the append-only triggers below are not
        // disturbed and every existing visit reads back as kind 'visit'.
        let columns = try columnNames(h, table: "journal")
        if !columns.contains("kind") {
            try exec(h, "ALTER TABLE journal ADD COLUMN kind TEXT NOT NULL DEFAULT 'visit';")
        }
        if !columns.contains("corrects_seq") {
            try exec(h, "ALTER TABLE journal ADD COLUMN corrects_seq INTEGER;")
        }
        // Journals written before double-in have no in-rule. The default is straight, which is what
        // every match in them actually was — the engine refused any other value at the time — so this
        // is a fact being written down, not a guess being made.
        if try !columnNames(h, table: "local_match").contains("in_rule") {
            try exec(h, "ALTER TABLE local_match ADD COLUMN in_rule TEXT NOT NULL DEFAULT 'straight';")
        }
        // Matches written before the device kept a book of who plays on it (ADR-016). Null is the
        // honest value: nobody knows who those two names were, and a prompt can ask later. It is
        // never guessed at, because guessing is how one person's history becomes another's.
        let matchColumnNames = try columnNames(h, table: "local_match")
        if !matchColumnNames.contains("home_player_id") {
            try exec(h, "ALTER TABLE local_match ADD COLUMN home_player_id TEXT;")
        }
        if !matchColumnNames.contains("away_player_id") {
            try exec(h, "ALTER TABLE local_match ADD COLUMN away_player_id TEXT;")
        }
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
                               throw_first, started_at, device_id, in_rule, home_player_id, away_player_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, [
                .text(id.value), .text(m.homeName), .text(m.awayName), .int(Int64(m.startingScore)),
                .text(m.outRule.rawValue), .text(m.legsMode == .bestOf ? "bestOf" : "firstTo"),
                .int(Int64(m.legsTarget)), .text(m.throwFirst.rawValue),
                .text(Journal.iso.string(from: startedAt)), .text(deviceId.value), .text(m.inRule.rawValue),
                m.homePlayerId.map { Param.text($0) } ?? .null,
                m.awayPlayerId.map { Param.text($0) } ?? .null,
            ])
        return try match(id)
    }

    public func match(_ id: MatchId) throws -> MatchRecord {
        var found: MatchRecord?
        try run("SELECT \(Journal.matchColumns) FROM local_match WHERE match_id = ?;", [.text(id.value)]) { s in
            found = Journal.record(from: s)
        }
        guard let found else { throw JournalError.matchNotFound(id.value) }
        return found
    }

    /// Every match on this device, newest first.
    public func matches() throws -> [MatchRecord] {
        var out: [MatchRecord] = []
        try run("SELECT \(Journal.matchColumns) FROM local_match ORDER BY started_at DESC, rowid DESC;", []) { s in
            out.append(Journal.record(from: s))
        }
        return out
    }

    /// Named, in this order, so a column added by ALTER cannot silently shift the ones below it.
    /// `SELECT *` was doing exactly that, and adding in_rule was the change that would have found it.
    static let matchColumns = """
        match_id, home_name, away_name, starting_score, out_rule, legs_mode, legs_target, \
        throw_first, started_at, in_rule, home_player_id, away_player_id
        """

    private static func record(from s: OpaquePointer) -> MatchRecord {
        MatchRecord(
            id: MatchId(text(s, 0)),
            homeName: text(s, 1),
            awayName: text(s, 2),
            startingScore: Int(sqlite3_column_int64(s, 3)),
            inRule: InRule(rawValue: text(s, 9)) ?? .straight,
            outRule: OutRule(rawValue: text(s, 4)) ?? .double,
            legsMode: text(s, 5) == "firstTo" ? .firstTo : .bestOf,
            legsTarget: Int(sqlite3_column_int64(s, 6)),
            throwFirst: Seat(rawValue: text(s, 7)) ?? .home,
            startedAt: iso.date(from: text(s, 8)) ?? Date(timeIntervalSince1970: 0),
            homePlayerId: sqlite3_column_type(s, 10) == SQLITE_NULL ? nil : text(s, 10),
            awayPlayerId: sqlite3_column_type(s, 11) == SQLITE_NULL ? nil : text(s, 11)
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
            // A retired or abandoned match takes no more darts (PD-016). Inside the transaction, so
            // the check and the insert cannot be separated by another writer.
            if let already = Journal.ending(try entries(for: matchId)) {
                throw JournalError.alreadyEnded(already)
            }
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
                                kind: .visit, seat: seat, visitTotal: visitTotal, dartsUsed: dartsUsed,
                                dartsAtDouble: dartsAtDouble, correctsSeq: nil, occurredAt: occurredAt)
        } catch {
            try? Journal.exec(handle, "ROLLBACK;")
            throw error
        }
    }

    /// Strikes the most recent standing visit from the record by appending a retraction that
    /// supersedes it. Nothing is deleted: the struck row stays, replay skips it, and the statistics
    /// never see it. Only the last standing visit can be struck; striking again walks one further
    /// back. PD-004: a local match needs no one's approval for this; an online match will need the
    /// opponent's, and that flow is not built.
    @discardableResult
    public func retractLastVisit(in matchId: MatchId,
                                 occurredAt: Date = Date(), commandId: String = UUID().uuidString) throws -> JournalEntry {
        try Journal.exec(handle, "BEGIN IMMEDIATE;")
        do {
            let all = try entries(for: matchId)
            // An ended match is closed to corrections too (PD-016). Undoing the last visit of a
            // retired match would change the scoreline behind a result that has already been given
            // to somebody, which is the moving claim an ending exists to stop.
            if let already = Journal.ending(all) {
                throw JournalError.alreadyEnded(already)
            }
            guard let target = Journal.standingVisits(all).last else {
                throw JournalError.nothingToRetract
            }
            var next: Int64 = 1
            try run("SELECT COALESCE(MAX(device_seq), 0) + 1 FROM journal WHERE match_id = ? AND device_id = ?;",
                    [.text(matchId.value), .text(deviceId.value)]) { s in
                next = sqlite3_column_int64(s, 0)
            }
            try run("""
                INSERT INTO journal (match_id, device_id, device_seq, command_id, kind, seat, visit_total,
                                     darts_used, darts_at_double, corrects_seq, occurred_at)
                VALUES (?, ?, ?, ?, 'retraction', ?, 0, NULL, NULL, ?, ?);
                """, [
                    .text(matchId.value), .text(deviceId.value), .int(next), .text(commandId),
                    .text(target.seat.rawValue), .int(target.deviceSeq), .text(Journal.iso.string(from: occurredAt)),
                ])
            try Journal.exec(handle, "COMMIT;")
            return JournalEntry(matchId: matchId, deviceId: deviceId, deviceSeq: next, commandId: commandId,
                                kind: .retraction, seat: target.seat, visitTotal: 0, dartsUsed: nil,
                                dartsAtDouble: nil, correctsSeq: target.deviceSeq, occurredAt: occurredAt)
        } catch {
            try? Journal.exec(handle, "ROLLBACK;")
            throw error
        }
    }

    // MARK: - attestation (PD-011)

    /// Records that a player agrees, or does not agree, with the result as it currently stands.
    ///
    /// **This is an assertion by a person, not corroboration by a second device.** Two people at one
    /// phone is the weakest form of the trust model's `participant-confirmed`, and the client says
    /// so where it shows it. What it does give is the thing PD-002 requires before any result can
    /// ever rate: two competitors on the record, rather than one person's word.
    ///
    /// Written as an ordinary append, so it is durable on the same terms as a visit and cannot be
    /// edited afterwards. Nothing is ever removed by it.
    @discardableResult
    public func attest(_ matchId: MatchId, seat: Seat, agrees: Bool,
                       occurredAt: Date = Date(), commandId: String = UUID().uuidString) throws -> JournalEntry {
        let kind: JournalEntry.Kind = agrees ? .confirmation : .contest
        try Journal.exec(handle, "BEGIN IMMEDIATE;")
        do {
            var next: Int64 = 1
            try run("SELECT COALESCE(MAX(device_seq), 0) + 1 FROM journal WHERE match_id = ? AND device_id = ?;",
                    [.text(matchId.value), .text(deviceId.value)]) { s in
                next = sqlite3_column_int64(s, 0)
            }
            try run("""
                INSERT INTO journal (match_id, device_id, device_seq, command_id, kind, seat, visit_total,
                                     darts_used, darts_at_double, corrects_seq, occurred_at)
                VALUES (?, ?, ?, ?, ?, ?, 0, NULL, NULL, NULL, ?);
                """, [
                    .text(matchId.value), .text(deviceId.value), .int(next), .text(commandId),
                    .text(kind.rawValue), .text(seat.rawValue), .text(Journal.iso.string(from: occurredAt)),
                ])
            try Journal.exec(handle, "COMMIT;")
            return JournalEntry(matchId: matchId, deviceId: deviceId, deviceSeq: next, commandId: commandId,
                                kind: kind, seat: seat, visitTotal: 0, dartsUsed: nil,
                                dartsAtDouble: nil, correctsSeq: nil, occurredAt: occurredAt)
        } catch {
            try? Journal.exec(handle, "ROLLBACK;")
            throw error
        }
    }

    // MARK: - ending a match short (PD-016)

    /// Closes a match that will not be played out: a retirement, which has a winner, or an
    /// abandonment, which does not.
    ///
    /// **An ending is final.** Nothing here retracts it, and `append` refuses a visit afterwards.
    /// That is a deliberate departure from PD-004, which makes a mis-keyed *visit* undoable: a visit
    /// is a transcription and endings are declarations, taken behind a confirmation on the screen.
    /// If an ending could be undone the match could un-end, and "the result" would be a claim that
    /// moves — precisely what the attestation in PD-011 exists to pin down. A match ended in error
    /// stays ended and says what happened, which is what an evidence journal is for.
    @discardableResult
    public func end(_ matchId: MatchId, as ending: Ending,
                    occurredAt: Date = Date(), commandId: String = UUID().uuidString) throws -> JournalEntry {
        try Journal.exec(handle, "BEGIN IMMEDIATE;")
        do {
            let all = try entries(for: matchId)
            if let already = Journal.ending(all) {
                throw JournalError.alreadyEnded(already)
            }
            var next: Int64 = 1
            try run("SELECT COALESCE(MAX(device_seq), 0) + 1 FROM journal WHERE match_id = ? AND device_id = ?;",
                    [.text(matchId.value), .text(deviceId.value)]) { s in
                next = sqlite3_column_int64(s, 0)
            }
            // An abandonment has no seat, and the column will not take a null. `home` is written as
            // a placeholder and is NEVER read back for an abandonment — `Journal.ending` branches on
            // the kind before it looks at the seat. `abandonmentIgnoresTheSeatItStores` proves the
            // placeholder is inert by storing the other one and reading the same answer, which is a
            // stronger guarantee than this comment.
            let seat: Seat = { if case let .retired(by) = ending { return by } else { return .home } }()
            try run("""
                INSERT INTO journal (match_id, device_id, device_seq, command_id, kind, seat, visit_total,
                                     darts_used, darts_at_double, corrects_seq, occurred_at)
                VALUES (?, ?, ?, ?, ?, ?, 0, NULL, NULL, NULL, ?);
                """, [
                    .text(matchId.value), .text(deviceId.value), .int(next), .text(commandId),
                    .text(ending.kind.rawValue), .text(seat.rawValue), .text(Journal.iso.string(from: occurredAt)),
                ])
            try Journal.exec(handle, "COMMIT;")
            return JournalEntry(matchId: matchId, deviceId: deviceId, deviceSeq: next, commandId: commandId,
                                kind: ending.kind, seat: seat, visitTotal: 0, dartsUsed: nil,
                                dartsAtDouble: nil, correctsSeq: nil, occurredAt: occurredAt)
        } catch {
            try? Journal.exec(handle, "ROLLBACK;")
            throw error
        }
    }

    /// How this match ended short, if it did. `nil` means it is still open or was played out.
    public func ending(for matchId: MatchId) throws -> Ending? {
        Journal.ending(try entries(for: matchId))
    }

    public static func ending(_ entries: [JournalEntry]) -> Ending? {
        // The earliest ending wins. `end` refuses a second one, so there is normally only ever one;
        // reading the earliest rather than the latest means a file that somehow carries two still
        // answers with the ending that actually stopped play.
        guard let row = entries.filter({ $0.kind.endsTheMatch }).min(by: { $0.deviceSeq < $1.deviceSeq })
        else { return nil }
        return row.kind == .retirement ? .retired(by: row.seat) : .abandoned
    }

    /// Who stands behind the result as it is recorded right now.
    public struct Standing: Equatable, Sendable {
        public let confirmed: Set<Seat>
        public let contested: Set<Seat>
        /// A visit or a retraction was written **after** the last attestation, so what somebody
        /// agreed to is no longer what is recorded. The attestation is not deleted — nothing here
        /// ever is — it simply no longer describes this result, and the label says so.
        public let stale: Bool

        public init(confirmed: Set<Seat>, contested: Set<Seat>, stale: Bool) {
            self.confirmed = confirmed
            self.contested = contested
            self.stale = stale
        }

        public var bothConfirmed: Bool { confirmed == Set(Seat.allCases) && !stale }
        public var anyContest: Bool { !contested.isEmpty && !stale }
    }

    /// Reads the attestations for a match and works out whether they still apply.
    ///
    /// Staleness is decided by `device_seq` alone: it is monotonic per device, so on the one phone
    /// that scored this match it is a total order, and "a scoring row came after the last
    /// attestation" is exactly "somebody changed the result after agreeing it".
    public func standing(for matchId: MatchId) throws -> Standing {
        Journal.standing(try entries(for: matchId))
    }

    public static func standing(_ entries: [JournalEntry]) -> Standing {
        let attestations = entries.filter { $0.kind == .confirmation || $0.kind == .contest }
        guard let lastAttestation = attestations.map(\.deviceSeq).max() else {
            return Standing(confirmed: [], contested: [], stale: false)
        }
        // Anything that changes what the result IS — a visit, a retraction, or an ending (PD-016) —
        // overtakes an agreement. Retiring after both players confirmed a scoreline hands the match
        // to somebody neither of them agreed had won it.
        let changedAfter = entries.contains {
            $0.kind.changesTheResult && $0.deviceSeq > lastAttestation
        }
        // The last word each player said. Somebody who contests and then agrees has agreed.
        var latest: [Seat: JournalEntry] = [:]
        for a in attestations.sorted(by: { $0.deviceSeq < $1.deviceSeq }) { latest[a.seat] = a }
        return Standing(
            confirmed: Set(latest.filter { $0.value.kind == .confirmation }.keys),
            contested: Set(latest.filter { $0.value.kind == .contest }.keys),
            stale: changedAfter)
    }

    /// The visits that stand: rows of kind `visit` that no retraction supersedes, in order.
    public static func standingVisits(_ entries: [JournalEntry]) -> [JournalEntry] {
        // Only a retraction supersedes; an attestation's corrects_seq is null, and a row of a kind
        // this build cannot read is not allowed to strike a visit it cannot be shown to refer to.
        let superseded = Set(entries.filter { $0.kind == .retraction }.compactMap { $0.correctsSeq })
        return entries.filter { $0.kind.isScoring && !superseded.contains($0.deviceSeq) }
    }

    /// Every committed row for a match — visits and retractions — in the order committed on this device.
    public func entries(for matchId: MatchId) throws -> [JournalEntry] {
        var out: [JournalEntry] = []
        try run("""
            SELECT match_id, device_id, device_seq, command_id, seat, visit_total, darts_used, darts_at_double, occurred_at,
                   kind, corrects_seq
            FROM journal WHERE match_id = ? ORDER BY rowid;
            """, [.text(matchId.value)]) { s in
            out.append(JournalEntry(
                matchId: MatchId(Journal.text(s, 0)),
                deviceId: DeviceId(Journal.text(s, 1)),
                deviceSeq: sqlite3_column_int64(s, 2),
                commandId: Journal.text(s, 3),
                // NOT `?? .visit`. A kind this build does not know is a row it cannot interpret,
                // and interpreting it as a visit would put a score in the match that nobody threw.
                kind: JournalEntry.Kind(rawValue: Journal.text(s, 9)) ?? .unknown,
                seat: Seat(rawValue: Journal.text(s, 4)) ?? .home,
                visitTotal: Int(sqlite3_column_int64(s, 5)),
                dartsUsed: Journal.optionalInt(s, 6),
                dartsAtDouble: Journal.optionalInt(s, 7),
                correctsSeq: sqlite3_column_type(s, 10) == SQLITE_NULL ? nil : sqlite3_column_int64(s, 10),
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

        let all = try entries(for: id)
        // A row this build cannot interpret might have been a visit. Replaying around it would
        // produce a state that looks right and is not, so the journal says so instead.
        if let alien = all.first(where: { $0.kind == .unknown }) {
            throw JournalError.replayRejected(seq: alien.deviceSeq, reason: "UNKNOWN_ROW_KIND")
        }
        for e in Journal.standingVisits(all) {
            guard let command = e.command else { continue }
            let leg = state.currentLeg
            let before = state.remaining[e.seat.playerId] ?? 0
            switch Engine.apply(state, command) {
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

    // MARK: - a person's history (ADR-016)

    /// Everything this device can honestly say about one person's darts.
    public struct PersonHistory: Sendable {
        public let visits: [ReplayedVisit]
        public let matches: Int
        public let legsWon: Int
        /// Matches of theirs whose rows would not replay. Counted and reported, never dropped —
        /// an average computed over the readable half is a different number, not a smaller sample.
        public let unreadable: Int
        /// The out-rules across their matches. More than one means the checkout figures cannot be
        /// pooled, because "was this visit thrown from a finishable position" depends on the rule.
        public let outRules: Set<String>
        /// Matches of theirs that were abandoned (PD-016). Their darts are in `visits` — those were
        /// thrown and are as real as any other — but the match produced no result, so it is counted
        /// separately rather than folded into a record of matches played out.
        public let abandoned: Int
        /// Matches of theirs that ended in a retirement, by either player. A result, and counted as
        /// one; named separately because a season with six of them is worth being able to see.
        public let retired: Int
    }

    /// Replays every match a person is named in and returns their visits, with legs renumbered.
    ///
    /// The renumbering is the part that would be a defect to skip: leg 1 of one match and leg 1 of
    /// another are different legs, and pooling them would merge two players' best legs into one and
    /// put six visits into a first-nine average. This repository has made that exact mistake once
    /// already, by sharing visit ordinals between the two competitors.
    public func history(of personId: String) throws -> PersonHistory {
        var pooled: [ReplayedVisit] = []
        var legOffset = 0
        var matches = 0, legsWon = 0, unreadable = 0, abandoned = 0, retired = 0
        var outRules: Set<String> = []

        for record in try self.matches() {
            let seats = Seat.allCases.filter { record.playerId($0) == personId }
            guard !seats.isEmpty else { continue }
            matches += 1
            outRules.insert(record.outRule.rawValue)
            do {
                switch try ending(for: record.id) {
                case .abandoned: abandoned += 1
                case .retired: retired += 1
                case nil: break
                }
                let replayed = try replayVisits(record.id)
                let legsHere = replayed.visits.map(\.legOrdinal).max() ?? 0
                for seat in seats {
                    legsWon += replayed.state.legsWonTotal[seat.playerId] ?? 0
                    for v in replayed.visits where v.seat == seat {
                        pooled.append(ReplayedVisit(
                            seat: v.seat, legOrdinal: legOffset + v.legOrdinal, visitOrdinal: v.visitOrdinal,
                            visitTotal: v.visitTotal, dartsUsed: v.dartsUsed, dartsAtDouble: v.dartsAtDouble,
                            remainingBefore: v.remainingBefore, remainingAfter: v.remainingAfter,
                            bust: v.bust, wonLeg: v.wonLeg))
                    }
                }
                legOffset += legsHere
            } catch {
                unreadable += 1
            }
        }
        return PersonHistory(visits: pooled, matches: matches, legsWon: legsWon,
                             unreadable: unreadable, outRules: outRules,
                             abandoned: abandoned, retired: retired)
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
