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

/// One configuration's result.
///
/// Named ProbeResult rather than Measurement deliberately: `Foundation.Measurement<UnitType>`
/// exists, and any file that imports XCTest or Foundation gets an ambiguous type lookup instead of
/// a helpful error. Deceptively cheap mistake — it cost a round trip to a machine with a Swift
/// toolchain, because nothing here could compile it.
public struct ProbeResult {
    public let configuration: Durability
    /// Every sample, in milliseconds, so a caller can compute whatever it needs.
    public let samplesMs: [Double]

    public var p50: Double { percentile(0.50) }
    public var p95: Double { percentile(0.95) }
    public var p99: Double { percentile(0.99) }
    public var worst: Double { samplesMs.max() ?? 0 }

    /// How long an explicit WAL checkpoint took after the visits, in milliseconds; nil for the
    /// rollback-journal configuration, which has no WAL to checkpoint.
    ///
    /// Two hundred visits never reach SQLite's automatic checkpoint threshold, so the WAL grows
    /// and is checkpointed at close — untimed. That meant `checkpoint_fullfsync`, one of the two
    /// pragmas ADR-006 names, was set by every configuration and exercised by none, and the visit
    /// that pays for a checkpoint in production appeared in no reported distribution. This is that
    /// cost, measured once per configuration under its own pragmas.
    public var checkpointMs: Double? = nil

    /// LATENCY_BUDGETS.md: event flushed to durable storage, P95 ≤ 20 ms, P99 ≤ 50 ms.
    ///
    /// No samples is not within budget. Every percentile of an empty result is 0.00, and 0.00 is
    /// under any budget, so a result that measured nothing used to print "meets".
    public var meetsBudget: Bool { !samplesMs.isEmpty && p95 <= 20.0 && p99 <= 50.0 }

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
    public static func measure(_ configuration: Durability, visits: Int = 200) throws -> ProbeResult {
        precondition(visits > 0, "a measurement of zero visits is not a measurement")

        let path = NSTemporaryDirectory() + "thro-durability-\(UUID().uuidString).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            for suffix in ["-wal", "-shm", "-journal"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let handle = db else {
            // sqlite3_open allocates a handle even on most failures, and it has to be closed.
            if let leaked = db { sqlite3_close(leaked) }
            throw ProbeError.sqlite("could not open \(path)")
        }
        defer { sqlite3_close(handle) }

        try configure(handle, configuration)

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

        // Every text parameter is bound with SQLITE_STATIC — a genuine null destructor — against a
        // buffer whose lifetime we control, which is why the constants are hoisted into these
        // nested closures rather than bound from a Swift String at the call site.
        //
        // The alternative, SQLITE_TRANSIENT, has no spelling in Swift that is not
        // `unsafeBitCast(-1, to: sqlite3_destructor_type.self)`: bit-casting an integer into a C
        // function pointer. That is undefined behaviour anywhere, and specifically hazardous on
        // arm64e, where function pointers are signed and an unauthenticated one may not survive the
        // crossing intact. Passing a Swift String straight to a `const char *` parameter has the
        // same shape of problem from the other end — the bridged buffer is guaranteed only for the
        // duration of that one call.
        let samples = try matchId.withCString { matchC -> [Double] in
            try occurredAt.withCString { occurredC -> [Double] in
                try "Home".withCString { homeC -> [Double] in
                    try "Away".withCString { awayC -> [Double] in
                        try writeVisits(
                            handle: handle, stmt: stmt, visits: visits,
                            matchC: matchC, occurredC: occurredC, homeC: homeC, awayC: awayC
                        )
                    }
                }
            }
        }

        // A probe that timed transactions which wrote nothing would report beautiful numbers for a
        // system that loses every dart, so the rows are counted before any of this is reported.
        let written = try count(handle, "SELECT count(*) FROM journal;")
        guard written == visits else {
            throw ProbeError.sqlite("journal holds \(written) rows after \(visits) committed visits")
        }

        var result = ProbeResult(configuration: configuration, samplesMs: samples)
        if configuration.journalMode.uppercased() == "WAL" {
            // TRUNCATE: checkpoint everything and reset the WAL, which is the checkpoint that
            // pays the full price — and, with checkpoint_fullfsync on, the barrier this
            // configuration promises for it.
            let start = DispatchTime.now()
            try exec(handle, "PRAGMA wal_checkpoint(TRUNCATE);")
            result.checkpointMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        }
        return result
    }

    private static func count(_ handle: OpaquePointer, _ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw ProbeError.sqlite("prepare failed: \(String(cString: sqlite3_errmsg(handle)))")
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw ProbeError.sqlite("\(sql) returned no row")
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// The timed loop. Takes the constant text parameters as pointers whose lifetime the caller
    /// guarantees for the whole call.
    private static func writeVisits(
        handle: OpaquePointer,
        stmt: OpaquePointer,
        visits: Int,
        matchC: UnsafePointer<CChar>,
        occurredC: UnsafePointer<CChar>,
        homeC: UnsafePointer<CChar>,
        awayC: UnsafePointer<CChar>
    ) throws -> [Double] {
        var samples: [Double] = []
        samples.reserveCapacity(visits)

        for seq in 1...visits {
            // Generating the identifier is not part of what durability costs, so it is not timed.
            let commandId = UUID().uuidString

            let elapsedNs: UInt64 = try commandId.withCString { commandC -> UInt64 in
                let start = DispatchTime.now()

                try exec(handle, "BEGIN IMMEDIATE;")
                sqlite3_reset(stmt)
                sqlite3_bind_int64(stmt, 1, Int64(seq))
                sqlite3_bind_text(stmt, 2, commandC, -1, nil)   // SQLITE_STATIC
                sqlite3_bind_text(stmt, 3, matchC, -1, nil)
                sqlite3_bind_text(stmt, 4, seq % 2 == 0 ? homeC : awayC, -1, nil)
                sqlite3_bind_int(stmt, 5, Int32(60))
                sqlite3_bind_null(stmt, 6)
                sqlite3_bind_null(stmt, 7)
                sqlite3_bind_text(stmt, 8, occurredC, -1, nil)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw ProbeError.sqlite("insert failed: \(String(cString: sqlite3_errmsg(handle)))")
                }
                // COMMIT is where the barrier happens, so it is inside the timed region.
                try exec(handle, "COMMIT;")

                let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds

                // Drop the statement's hold on commandC before this closure — and the buffer with
                // it — goes out of scope. With SQLITE_STATIC the pointer is the binding.
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                return ns
            }

            samples.append(Double(elapsedNs) / 1_000_000.0)
        }

        return samples
    }

    /// Applies a configuration's pragmas and then reads every one of them back.
    ///
    /// `PRAGMA journal_mode = WAL` does not fail when it cannot switch — it returns a row naming
    /// the mode the database is actually in, and `sqlite3_exec` with no callback throws that row
    /// away. So a refused change (an in-memory database, a read-only file, a build that ignores
    /// the pragma) left every pragma call reporting success and the measurement reporting numbers
    /// for a configuration that was not in force. The read-back makes that a thrown error with
    /// both values in it. The barrier guard would catch a gross version of this after the fact;
    /// this catches the exact one before a single visit is timed.
    ///
    /// Internal rather than private: KillProbe configures the same pragmas on the same handle,
    /// and a second copy of this would be a second place for the pragma order to drift.
    static func configure(_ handle: OpaquePointer, _ configuration: Durability) throws {
        // Order matters: fullfsync must be set before the journal mode change that fsyncs.
        try exec(handle, "PRAGMA fullfsync = \(configuration.fullFsync ? 1 : 0);")
        try exec(handle, "PRAGMA checkpoint_fullfsync = \(configuration.checkpointFullFsync ? 1 : 0);")
        try exec(handle, "PRAGMA journal_mode = \(configuration.journalMode);")
        try exec(handle, "PRAGMA synchronous = \(configuration.synchronous);")
        try verifyInForce(handle, configuration)
    }

    /// The value SQLite reports for `PRAGMA <name>;`, as text.
    static func pragmaValue(_ handle: OpaquePointer, _ name: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA \(name);", -1, &stmt, nil) == SQLITE_OK, let s = stmt else { return nil }
        defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW, let text = sqlite3_column_text(s, 0) else { return nil }
        return String(cString: text)
    }

    static func verifyInForce(_ handle: OpaquePointer, _ configuration: Durability) throws {
        // PRAGMA synchronous reads back as a number: OFF 0, NORMAL 1, FULL 2, EXTRA 3.
        let synchronousNumbers = ["OFF": "0", "NORMAL": "1", "FULL": "2", "EXTRA": "3"]
        let expected: [(String, String)] = [
            ("journal_mode", configuration.journalMode.lowercased()),
            ("synchronous", synchronousNumbers[configuration.synchronous.uppercased()] ?? configuration.synchronous),
            ("fullfsync", configuration.fullFsync ? "1" : "0"),
            ("checkpoint_fullfsync", configuration.checkpointFullFsync ? "1" : "0"),
        ]
        for (name, want) in expected {
            let got = pragmaValue(handle, name)?.lowercased() ?? "(no value)"
            guard got == want else {
                throw ProbeError.sqlite(
                    "PRAGMA \(name) requested \(want) but the database reports \(got) — "
                    + "the configuration '\(configuration.label)' is not in force, so nothing measured under it means anything"
                )
            }
        }
    }

    static func exec(_ handle: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw ProbeError.sqlite("\(sql): \(message)")
        }
    }
}

extension Probe {

    /// The guard the package's own tests apply on a Mac, made available to the device run.
    ///
    /// `testTheBarrierIsActuallyHappening` asserts that forcing a real storage barrier is slower
    /// than not forcing one — if it is not, the pragmas did not take effect and every number is
    /// meaningless. That assertion lives in XCTest, and the phone runs no XCTest: the app was built
    /// with Testing System: None, and `ProbeView` calls `Probe.measure` and displays. So the one
    /// run that decides the architecture was the only one of the three the guard never covered,
    /// and the ADR's first record of it said otherwise. This is the same comparison, on the same
    /// two configurations, over the results the device actually produced.
    public struct BarrierGuard: Equatable {
        public let relaxedP50: Double
        public let barrierP50: Double
        /// True when the real barrier's median is strictly slower than the relaxed one's.
        public var holds: Bool { barrierP50 > relaxedP50 }
        public var line: String {
            let r = String(format: "%.2f", relaxedP50)
            let b = String(format: "%.2f", barrierP50)
            return holds
                ? "THRO-PROBE-GUARD ok: fullfsync P50 \(b) ms > relaxed P50 \(r) ms"
                : "THRO-PROBE-GUARD FAILED: fullfsync P50 \(b) ms is not slower than relaxed P50 \(r) ms"
                  + " — the pragmas did not take effect and every row above is meaningless"
        }
    }

    /// One line that makes a captured report attributable on its own: the raw hardware identifier
    /// ADR-006 records (`iPhone15,3`, `Mac17,3`), the OS version and build, the sample count, and
    /// whether this is the Simulator — whose numbers are the Mac's SSD and answer a different
    /// question. A block of sixteen figures with none of this was pasted into the ADR by hand once;
    /// the attribution should travel with the numbers.
    public static func environmentLine(visits: Int?) -> String {
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let visitsText = visits.map(String.init) ?? "?"
        return "THRO-PROBE-ENV model=\(hardwareModel()) os=\"\(os)\" visits=\(visitsText) simulator=\(simulator)"
    }

    /// `hw.model` on macOS (`Mac17,3`); the machine field of `uname` elsewhere (`iPhone15,3`).
    static func hardwareModel() -> String {
        #if os(macOS)
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
        #else
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
        #endif
    }

    /// Nil when the results do not include both the relaxed and the real-barrier configuration.
    public static func barrierGuard(_ results: [ProbeResult]) -> BarrierGuard? {
        let relaxedLabel = Durability.candidates[0].label
        let barrierLabel = Durability.candidates[2].label
        guard let relaxed = results.first(where: { $0.configuration.label == relaxedLabel }),
              let barrier = results.first(where: { $0.configuration.label == barrierLabel }) else {
            return nil
        }
        return BarrierGuard(relaxedP50: relaxed.p50, barrierP50: barrier.p50)
    }

    /// Print the measured table to stdout, in the same shape the package's tests print on a Mac.
    ///
    /// This exists so an on-device run can be captured verbatim rather than read off the screen:
    /// ADR-006 records these figures as evidence, and a hand-copied percentile is not evidence of
    /// the same quality as a captured one. It reports, and nothing else — no thresholds are
    /// applied here that are not already in `ProbeResult.meetsBudget`.
    public static func printReport(_ results: [ProbeResult]) {
        print(reportText(results))
        fflush(stdout)
    }

    /// Where the app keeps every block it has printed, one after another, so a run taken with no
    /// cable attached — nothing capturing stdout — is still recoverable verbatim later:
    ///
    ///     xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
    ///       --domain-identifier com.thro.ThroProbe --source Documents/thro-probe-report.txt \
    ///       --destination ./thro-probe-report.txt
    ///
    /// Numbers read off the screen are evidence of a lower grade than captured ones; this is what
    /// turns a screen-read run back into a captured one.
    public static func reportFilePath() -> String {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("thro-probe-report.txt").path
    }

    /// Appends the block for `results`, stamped, to the report file. Returns the path written.
    @discardableResult
    public static func saveReport(_ results: [ProbeResult], to path: String = reportFilePath()) throws -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "THRO-PROBE-RUN \(stamp)\n" + reportText(results) + "\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
        } else {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        return path
    }

    /// The captured block as text: attribution, table, incompleteness, guard.
    public static func reportText(_ results: [ProbeResult]) -> String {
        var out: [String] = []
        func print(_ line: String) { out.append(line) }

        print("")
        print("THRO-PROBE-BEGIN")
        print("  " + environmentLine(visits: results.first?.samplesMs.count))
        // Pad in Swift rather than with a %-56@ format width: on Apple platforms String(format:)
        // ignores field widths for %@, so the format-string version silently produces a ragged
        // table that is fiddly to read off a phone.
        func column(_ text: String) -> String {
            text.count >= 56 ? text : text + String(repeating: " ", count: 56 - text.count)
        }

        print("  " + column("configuration")
              + ["P50", "P95", "P99", "worst", "ckpt"].map { $0.leftPadded(to: 7) }.joined()
              + "  budget")
        for r in results {
            let cells = [r.p50, r.p95, r.p99, r.worst]
                .map { String(format: "%.2f", $0).leftPadded(to: 7) }
                .joined()
            let checkpoint = (r.checkpointMs.map { String(format: "%.2f", $0) } ?? "-").leftPadded(to: 7)
            print("  " + column(r.configuration.label) + cells + checkpoint
                  + "  " + (r.meetsBudget ? "meets" : "EXCEEDS"))
        }
        if results.count < Durability.candidates.count {
            // A configuration that threw used to vanish from this table without a trace, and the
            // error reached only the screen. The table must say it is short.
            print("  THRO-PROBE-INCOMPLETE \(results.count) of \(Durability.candidates.count) configurations reported"
                  + " — see THRO-PROBE-ERROR lines above; do not record this table as complete")
        }
        if let guardResult = barrierGuard(results) {
            print("  " + guardResult.line)
        }
        print("THRO-PROBE-END")
        print("")
        return out.joined(separator: "\n")
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
