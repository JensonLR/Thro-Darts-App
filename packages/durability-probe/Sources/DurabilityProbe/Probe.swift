import Foundation
import SQLite3

/// Measures how long it takes to make one recorded visit durable.
///
/// ADR-006's durability rule is non-negotiable: the command is flushed to the journal **before** it
/// is applied and acknowledged. Rendering first and persisting second loses a dart on any crash
/// between, and the player will not notice until the scores disagree with the board.
///
/// The cost of honouring that rule is a real number on real hardware, and ADR-006 says it must be
/// measured rather than assumed — because if it exceeds the budget, the fallback is a raw
/// append-only write-ahead file with the database demoted to a projection. That is a second storage
/// engine on both clients, not a tweak, so the decision has to be made on evidence.

/// SQLite's transaction-safety knobs, as candidate configurations.
public struct Durability: Sendable, CustomStringConvertible {
    public let journalMode: String
    public let synchronous: String
    /// **Apple-specific and the whole reason this probe exists.** On Apple platforms `fsync` does
    /// not flush the drive's write cache; `PRAGMA fullfsync` is what issues the real barrier.
    public let fullFsync: Bool
    public let checkpointFullFsync: Bool
    public let label: String

    public init(
        label: String,
        journalMode: String,
        synchronous: String,
        fullFsync: Bool,
        checkpointFullFsync: Bool
    ) {
        self.label = label
        self.journalMode = journalMode
        self.synchronous = synchronous
        self.fullFsync = fullFsync
        self.checkpointFullFsync = checkpointFullFsync
    }

    public var description: String {
        "\(label) [journal=\(journalMode) sync=\(synchronous) fullfsync=\(fullFsync) ckpt=\(checkpointFullFsync)]"
    }

    /// The configurations worth distinguishing, weakest first.
    ///
    /// `relaxed` is included precisely because it is the one that looks fine and is not: it survives
    /// process death but **not power loss**, which is the failure that loses an acknowledged
    /// competitive visit with no repair path.
    public static let candidates: [Durability] = [
        Durability(label: "relaxed (survives process death, NOT power loss)",
                   journalMode: "WAL", synchronous: "NORMAL",
                   fullFsync: false, checkpointFullFsync: false),
        Durability(label: "synchronous=FULL, no Apple barrier",
                   journalMode: "WAL", synchronous: "FULL",
                   fullFsync: false, checkpointFullFsync: false),
        Durability(label: "synchronous=FULL + fullfsync (the real barrier on Apple)",
                   journalMode: "WAL", synchronous: "FULL",
                   fullFsync: true, checkpointFullFsync: true),
        Durability(label: "rollback journal + FULL + fullfsync",
                   journalMode: "DELETE", synchronous: "FULL",
                   fullFsync: true, checkpointFullFsync: true),
    ]
}

public struct Measurement {
    public let configuration: Durability
    /// Every sample, in milliseconds, so a caller can compute whatever it needs.
    public let samplesMs: [Double]

    public var p50: Double { percentile(0.50) }
    public var p95: Double { percentile(0.95) }
    public var p99: Double { percentile(0.99) }
    public var worst: Double { samplesMs.max() ?? 0 }

    /// LATENCY_BUDGETS.md: event flushed to durable storage, P95 ≤ 20 ms, P99 ≤ 50 ms.
    public var meetsBudget: Bool { p95 <= 20.0 && p99 <= 50.0 }

    private func percentile(_ q: Double) -> Double {
        guard !samplesMs.isEmpty else { return 0 }
        let sorted = samplesMs.sorted()
        // Nearest-rank, so a reported P99 is a sample that actually occurred rather than an
        // interpolation between two that did not.
        let rank = Int((q * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }
}

public enum ProbeError: Error {
    case sqlite(String)
}

public enum Probe {

    /// Writes [visits] synthetic visits, one durable transaction each, and times every one.
    ///
    /// One transaction per visit on purpose: that is what the durability rule costs. Batching would
    /// produce a much prettier number that describes a system which loses darts.
    public static func measure(_ configuration: Durability, visits: Int = 200) throws -> Measurement {
        let path = NSTemporaryDirectory() + "thro-durability-\(UUID().uuidString).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            for suffix in ["-wal", "-shm", "-journal"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let handle = db else {
            throw ProbeError.sqlite("could not open \(path)")
        }
        defer { sqlite3_close(handle) }

        // Order matters: fullfsync must be set before the journal mode change that fsyncs.
        try exec(handle, "PRAGMA fullfsync = \(configuration.fullFsync ? 1 : 0);")
        try exec(handle, "PRAGMA checkpoint_fullfsync = \(configuration.checkpointFullFsync ? 1 : 0);")
        try exec(handle, "PRAGMA journal_mode = \(configuration.journalMode);")
        try exec(handle, "PRAGMA synchronous = \(configuration.synchronous);")

        // The journal is append-only and carries the command, not a projection of it.
        try exec(handle, """
            CREATE TABLE journal (
              device_seq INTEGER PRIMARY KEY,
              command_id TEXT NOT NULL,
              match_id   TEXT NOT NULL,
              player     TEXT NOT NULL,
              visit_total INTEGER NOT NULL,
              darts_used INTEGER,
              darts_at_double INTEGER,
              occurred_at TEXT NOT NULL
            );
            """)

        var statement: OpaquePointer?
        let insert = """
            INSERT INTO journal
              (device_seq, command_id, match_id, player, visit_total, darts_used, darts_at_double, occurred_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
        guard sqlite3_prepare_v2(handle, insert, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw ProbeError.sqlite("prepare failed: \(String(cString: sqlite3_errmsg(handle)))")
        }
        defer { sqlite3_finalize(stmt) }

        let matchId = UUID().uuidString
        let occurredAt = ISO8601DateFormatter().string(from: Date())
        var samples: [Double] = []
        samples.reserveCapacity(visits)

        for seq in 1...visits {
            let commandId = UUID().uuidString
            let start = DispatchTime.now()

            try exec(handle, "BEGIN IMMEDIATE;")
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_int64(stmt, 1, Int64(seq))
            bindText(stmt, 2, commandId)
            bindText(stmt, 3, matchId)
            bindText(stmt, 4, seq % 2 == 0 ? "Home" : "Away")
            sqlite3_bind_int(stmt, 5, Int32(60))
            sqlite3_bind_null(stmt, 6)
            sqlite3_bind_null(stmt, 7)
            bindText(stmt, 8, occurredAt)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw ProbeError.sqlite("insert failed: \(String(cString: sqlite3_errmsg(handle)))")
            }
            // COMMIT is where the barrier happens, so it is inside the timed region.
            try exec(handle, "COMMIT;")

            let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            samples.append(Double(elapsedNs) / 1_000_000.0)
        }

        return Measurement(configuration: configuration, samplesMs: samples)
    }

    private static func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        // SQLITE_TRANSIENT: SQLite copies the bytes, which it must, because the Swift string may be
        // gone before the statement runs.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, index, value, -1, transient)
    }

    private static func exec(_ handle: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw ProbeError.sqlite("\(sql): \(message)")
        }
    }
}
