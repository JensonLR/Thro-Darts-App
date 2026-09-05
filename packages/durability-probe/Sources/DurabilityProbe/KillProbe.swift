import Foundation
import SQLite3

/// Kills the process mid-visit and checks that nothing acknowledged was lost.
///
/// ADR-006 says the durability setting is "raised and validated with real kill tests and power-cut
/// tests on device — not assumed", and ADR-011 requires the kill test on every release candidate.
/// `Probe` cannot answer this: it measures how long the barrier takes, not whether the barrier
/// holds. A configuration can be fast and wrong.
///
/// The two tests are not interchangeable and this is the weaker of them:
///
/// - **This kill test** covers *process* death — the app is terminated, the operating system and
///   the hardware keep running. Anything SQLite handed to the kernel survives, so this passes for
///   `synchronous=NORMAL` too. It proves the journal is not corrupted and no acknowledged visit
///   vanished.
/// - **The power-cut test**, still outstanding, covers loss of power, where anything sitting in the
///   drive's write cache is gone. That is the test `fullfsync` exists for, and the only one that
///   distinguishes a real barrier from one the drive merely claims.
///
/// Passing here is necessary and not sufficient. Do not let a green kill test be read as evidence
/// that the power-cut question is closed.
public enum KillProbe {

    /// The journal has to outlive the process, so it cannot live in the temporary directory the
    /// latency probe uses — the point is to reopen this exact file after the process is gone.
    public static func journalPath() -> String {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("thro-kill-test.sqlite").path
    }

    public static func removeJournal() {
        removeJournal(at: journalPath())
    }

    public static func removeJournal(at path: String) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    // MARK: - Phase one: write until killed

    /// Writes up to `maxVisits` visits to the journal at `path`, one durable transaction each,
    /// printing and flushing an acknowledgement after every commit. Returns the last sequence
    /// written once the cap is reached. Throws if a write fails.
    ///
    /// The loop is factored out of `writeUntilKilled` so its two terminal states can be tested in a
    /// process that is not about to be killed: reaching the cap, and a write failing. A write
    /// failure used to `return` from the loop, fall through to a clean `sqlite3_close` — which
    /// checkpoints the WAL and flushes everything the configuration under test had left in the
    /// kernel — and let `writeUntilKilled` return normally, so nothing upstream noticed and the
    /// scheduled kill later landed on a journal that had been fully quiesced for most of a
    /// minute. A run like that adjudicates as a clean pass and tests nothing. Now it throws.
    ///
    /// Every acknowledged sequence number is printed and the stream flushed immediately, because
    /// SIGKILL discards whatever is still sitting in the stdout buffer. An acknowledgement we fail
    /// to record makes the test under-claim rather than over-claim — the safe direction — but it
    /// also makes it blunt, and the flush costs nothing next to a storage barrier.
    @discardableResult
    public static func writeVisits(
        at path: String,
        _ configuration: Durability,
        maxVisits: Int,
        throttleMicroseconds: UInt32
    ) throws -> Int {
        precondition(maxVisits > 0, "a write phase of zero visits acknowledges nothing")

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let handle = db else {
            if let leaked = db { sqlite3_close(leaked) }
            throw ProbeError.sqlite("could not open \(path)")
        }
        // Closed on every exit. On the failure path this checkpoints whatever was in the WAL,
        // which is exactly the flush the test is trying to avoid — but a run whose writer failed is
        // void regardless (the scripts refuse to adjudicate one), so leaving the handle open would
        // buy nothing and would leak a connection in every test that exercises this path.
        defer { sqlite3_close(handle) }

        try Probe.exec(handle, "PRAGMA fullfsync = \(configuration.fullFsync ? 1 : 0);")
        try Probe.exec(handle, "PRAGMA checkpoint_fullfsync = \(configuration.checkpointFullFsync ? 1 : 0);")
        try Probe.exec(handle, "PRAGMA journal_mode = \(configuration.journalMode);")
        try Probe.exec(handle, "PRAGMA synchronous = \(configuration.synchronous);")
        try Probe.exec(handle, """
            CREATE TABLE IF NOT EXISTS journal (
              device_seq INTEGER PRIMARY KEY,
              match_id   TEXT NOT NULL,
              visit_total INTEGER NOT NULL,
              occurred_at TEXT NOT NULL
            );
            """)

        print("KILLTEST-WRITE-BEGIN \(configuration.label)")
        print("KILLTEST-PATH \(path)")
        fflush(stdout)

        // Resume after the highest sequence already present, so a second pass against an existing
        // journal extends it rather than colliding on the primary key.
        var startSeq = 0
        var countStmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT IFNULL(MAX(device_seq), 0) FROM journal;", -1, &countStmt, nil) == SQLITE_OK,
              let cs = countStmt else {
            throw ProbeError.sqlite("could not read the journal's highest sequence: \(String(cString: sqlite3_errmsg(handle)))")
        }
        if sqlite3_step(cs) == SQLITE_ROW { startSeq = Int(sqlite3_column_int64(cs, 0)) }
        sqlite3_finalize(cs)

        var statement: OpaquePointer?
        let insert = """
            INSERT INTO journal (device_seq, match_id, visit_total, occurred_at)
            VALUES (?, ?, ?, ?);
            """
        guard sqlite3_prepare_v2(handle, insert, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw ProbeError.sqlite("prepare failed: \(String(cString: sqlite3_errmsg(handle)))")
        }
        defer { sqlite3_finalize(stmt) }

        let matchId = UUID().uuidString
        let occurredAt = ISO8601DateFormatter().string(from: Date())

        // Same SQLITE_STATIC discipline as Probe: bind against buffers whose lifetime we control,
        // never a bridged Swift String, and never a bit-cast SQLITE_TRANSIENT.
        return try matchId.withCString { matchC -> Int in
            try occurredAt.withCString { occurredC -> Int in
                var seq = startSeq
                while seq - startSeq < maxVisits {
                    seq += 1
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                    sqlite3_bind_int64(stmt, 1, sqlite3_int64(seq))
                    sqlite3_bind_text(stmt, 2, matchC, -1, nil)
                    sqlite3_bind_int(stmt, 3, Int32(60 + (seq % 41)))
                    sqlite3_bind_text(stmt, 4, occurredC, -1, nil)

                    if sqlite3_step(stmt) != SQLITE_DONE {
                        let message = String(cString: sqlite3_errmsg(handle))
                        print("KILLTEST-WRITE-ERROR seq \(seq): \(message)")
                        fflush(stdout)
                        throw ProbeError.sqlite("write failed at seq \(seq): \(message)")
                    }
                    // Acknowledged only now: sqlite3_step has returned, so the durable write this
                    // configuration promises has completed. ADR-006's rule is that acknowledgement
                    // follows the flush, and this print is the acknowledgement.
                    print("KILLTEST-ACK \(seq)")
                    fflush(stdout)
                    if throttleMicroseconds > 0 { usleep(throttleMicroseconds) }
                }
                return seq
            }
        }
    }

    /// Writes visits under `configuration` and terminates the process partway through.
    ///
    /// SIGKILL rather than `exit()` on purpose. `exit()` runs atexit handlers and flushes buffers,
    /// which is precisely what a crash does not do; it would quietly test the happy path. SIGKILL
    /// cannot be caught or ignored, so the process stops between two instructions with no
    /// opportunity to tidy up — which is the event being simulated.
    ///
    /// The kill fires from a background thread after `killAfterMs`, so it lands wherever the writer
    /// happens to be, usually inside a transaction. That is the case worth testing: a torn write,
    /// not a clean stop between two of them.
    ///
    /// `maxVisits` caps the journal size. Under `relaxed` the writer manages well over a hundred
    /// thousand commits a minute, and an unbounded run produced a 270,000-row, 18 MB journal whose
    /// `integrity_check` took long enough on device to trip the iOS launch watchdog. But the cap
    /// is a size limit, not a stopping point the test tolerates: once it is reached the writer is
    /// idle, the kernel flushes everything within tens of seconds, and a kill or restart landing
    /// after that has nothing at risk. `KILLTEST-CAP-REACHED` is printed for exactly that reason,
    /// and the scripts treat a run that printed it as void.
    ///
    /// Never returns. The cap path parks the process so the terminating event still lands on a
    /// live app; the failure path throws so the caller can report it and stop.
    public static func writeUntilKilled(
        _ configuration: Durability,
        killAfterMs: Int,
        fresh: Bool,
        maxVisits: Int = 20_000,
        throttleMicroseconds: UInt32 = 0
    ) throws -> Never {
        if fresh { removeJournal() }

        let deadline = DispatchTime.now() + .milliseconds(killAfterMs)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: deadline) {
            print("KILLTEST-KILLING-NOW")
            fflush(stdout)
            kill(getpid(), SIGKILL)
        }

        let reached = try writeVisits(
            at: journalPath(), configuration,
            maxVisits: maxVisits, throttleMicroseconds: throttleMicroseconds
        )

        // The cap is reached but the process must stay alive: the event under test is the device
        // going down, and an app that has already exited cannot demonstrate anything about it.
        print("KILLTEST-CAP-REACHED \(reached)")
        fflush(stdout)
        while true { Thread.sleep(forTimeInterval: 1) }
    }

    // MARK: - Phase two: what survived

    public struct Report {
        public let opened: Bool
        public let integrity: String
        public let maxSeq: Int
        public let rowCount: Int
        /// Sequence numbers missing from 1...maxSeq. A hole means a write that was reported
        /// durable is not there, which is the failure this test exists to catch.
        public let holes: [Int]
        /// False when the file opened but holds no `journal` table. `sqlite3_open` creates an
        /// empty database where none existed, and an empty database passes `integrity_check`, so
        /// without this flag "the journal is not there" is indistinguishable from "the journal
        /// survived with nothing in it" — and both used to adjudicate as a pass.
        public var tableFound: Bool = true
        /// `PRAGMA journal_mode` as the file reports it. Printed so a reader can tell whether a
        /// missing `-wal` sidecar matters for this journal.
        public var journalMode: String = "unknown"

        public var contiguous: Bool { holes.isEmpty && rowCount == maxSeq }
        public var healthy: Bool { opened && integrity == "ok" && tableFound && rowCount > 0 && contiguous }
    }

    /// Whether a non-empty `-wal` sidecar sits alongside the journal at `path`.
    ///
    /// Ask this BEFORE opening the database. SQLite creates an empty sidecar the moment a
    /// connection reads a WAL-mode file, so an existence check made afterwards always says yes.
    /// Non-empty is the test that matters: a zero-length sidecar holds no commits.
    public static func hasWalSidecar(at path: String) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path + "-wal")
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        return size > 0
    }

    /// Reopens the app's own journal after the kill and reports what is actually in it.
    public static func inspect() throws -> Report {
        try inspect(at: journalPath())
    }

    /// Inspects a journal at an arbitrary path — a copy pulled off a device, for instance.
    ///
    /// The caller is responsible for the `-wal` sidecar being alongside the file. In WAL mode the
    /// most recent commits live there and nowhere else; inspecting the main database on its own
    /// once reported 269,811 rows for a journal that held 270,779, and turned that into a
    /// confident, entirely false "967 acknowledged visits lost". `journalMode` is reported so a
    /// caller can notice when that sidecar was needed.
    public static func inspect(at path: String) throws -> Report {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let handle = db else {
            if let leaked = db { sqlite3_close(leaked) }
            return Report(opened: false, integrity: "could not open", maxSeq: 0, rowCount: 0, holes: [])
        }
        defer { sqlite3_close(handle) }

        func scalarText(_ sql: String) -> String? {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else { return nil }
            defer { sqlite3_finalize(s) }
            guard sqlite3_step(s) == SQLITE_ROW, let text = sqlite3_column_text(s, 0) else { return nil }
            return String(cString: text)
        }

        // integrity_check is what distinguishes "we lost the tail" from "the file is damaged".
        // A torn write that corrupts the b-tree is a different and worse failure than one that
        // simply did not land, and the report should not blur them.
        let integrity = scalarText("PRAGMA integrity_check;") ?? "unknown"
        let journalMode = scalarText("PRAGMA journal_mode;") ?? "unknown"

        var maxSeq = 0
        var rowCount = 0
        var tableFound = false
        var aggStmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, "SELECT IFNULL(MAX(device_seq), 0), COUNT(*) FROM journal;", -1, &aggStmt, nil) == SQLITE_OK,
           let astmt = aggStmt {
            tableFound = true
            if sqlite3_step(astmt) == SQLITE_ROW {
                maxSeq = Int(sqlite3_column_int64(astmt, 0))
                rowCount = Int(sqlite3_column_int64(astmt, 1))
            }
            sqlite3_finalize(astmt)
        }

        var holes: [Int] = []
        if maxSeq != rowCount {
            var present = Set<Int>()
            var seqStmt: OpaquePointer?
            if sqlite3_prepare_v2(handle, "SELECT device_seq FROM journal;", -1, &seqStmt, nil) == SQLITE_OK,
               let sstmt = seqStmt {
                while sqlite3_step(sstmt) == SQLITE_ROW {
                    present.insert(Int(sqlite3_column_int64(sstmt, 0)))
                }
                sqlite3_finalize(sstmt)
            }
            holes = (1...max(maxSeq, 1)).filter { !present.contains($0) }
        }

        var report = Report(opened: true, integrity: integrity, maxSeq: maxSeq, rowCount: rowCount, holes: holes)
        report.tableFound = tableFound
        report.journalMode = journalMode
        return report
    }

    /// The pass rule, in one place.
    ///
    /// It used to live in two, and they disagreed. `printReport` compared `lastAck` against
    /// `maxSeq` alone and printed PASS; the exit path additionally required `report.healthy`,
    /// which includes the holes. So a journal with a hole below `maxSeq`, and an acknowledgement
    /// the surviving tail satisfies, printed
    ///
    ///     verdict           PASS — nothing acknowledged was lost
    ///
    /// to the console while exiting 2. A hole IS a lost acknowledgement: the writer reached a
    /// higher sequence, so the missing one had already returned from `sqlite3_step` and been
    /// reported durable. The runbook's stated pass condition says "no holes in the sequence" and
    /// the printed verdict did not check it.
    ///
    /// That is a false PASS on a durability test, and worse than the false FAIL this file already
    /// fixed once: a false failure gets investigated, a false pass gets believed.
    ///
    /// The shell scripts then grew a *third* copy of the rule — `LOST=$(( LAST_ACK - MAXSEQ ))` —
    /// with the same omission. They now run this function through the `adjudicate` executable
    /// instead, so there is nowhere left for the rule to drift.
    public enum Verdict: Equatable {
        case pass(String)
        case fail(String)
        /// Nothing to adjudicate: the journal is absent or empty, so the run measured nothing.
        /// Distinct from both outcomes on purpose — "no visits were lost" is not a true statement
        /// about a run in which no visits were written, and reporting it as one is the false pass
        /// this file keeps having to remove.
        case void(String)

        public var isPass: Bool {
            if case .pass = self { return true }
            return false
        }

        public var line: String {
            switch self {
            case .pass(let why): return "PASS — \(why)"
            case .fail(let why): return "FAIL — \(why)"
            case .void(let why): return "VOID — \(why)"
            }
        }

        /// 0 pass, 2 fail, 3 void. Distinct so a script can tell "lost data" from "measured
        /// nothing" without parsing prose.
        public var exitCode: Int32 {
            switch self {
            case .pass: return 0
            case .fail: return 2
            case .void: return 3
            }
        }
    }

    /// Adjudicates a reopened journal against the acknowledgements the console recorded.
    ///
    /// One-directional on purpose: the journal may legitimately hold *more* than was seen
    /// acknowledged, because SIGKILL discards a buffered acknowledgement for a write that did land.
    /// It may never hold less, and it may never have a gap.
    public static func verdict(_ report: Report, lastAck: Int?) -> Verdict {
        guard report.opened else {
            return .fail("the journal could not be reopened after the kill")
        }
        guard report.integrity == "ok" else {
            return .fail("integrity_check reported: \(report.integrity)")
        }
        if !report.holes.isEmpty {
            let named = report.holes.prefix(20).map(String.init).joined(separator: ",")
            let more = report.holes.count > 20 ? " (first 20 of \(report.holes.count))" : ""
            return .fail("\(report.holes.count) acknowledged visit(s) missing from the sequence: \(named)\(more)")
        }
        if let lastAck, lastAck > report.maxSeq {
            if !report.tableFound {
                return .fail("the journal table is gone entirely: console recorded \(lastAck) acknowledgement(s)")
            }
            return .fail("\(lastAck - report.maxSeq) acknowledged visit(s) missing: "
                         + "console recorded \(lastAck), journal holds \(report.maxSeq)")
        }
        guard report.tableFound else {
            return .void("no journal table at this path — the journal is absent or was never written, so this run measured nothing")
        }
        guard report.rowCount > 0 else {
            return .void("the journal is empty — nothing was acknowledged, so there is nothing to adjudicate")
        }
        return lastAck == nil
            ? .pass("journal intact and contiguous (no acknowledgement record supplied)")
            : .pass("nothing acknowledged was lost")
    }

    /// Prints the surviving state and the verdict.
    public static func printReport(_ report: Report, lastAck: Int?) {
        print("")
        print("KILLTEST-REPORT-BEGIN")
        print("  opened            \(report.opened)")
        print("  journal table     \(report.tableFound ? "found" : "MISSING")")
        print("  journal_mode      \(report.journalMode)")
        print("  integrity_check   \(report.integrity)")
        print("  max device_seq    \(report.maxSeq)")
        print("  rows              \(report.rowCount)")
        print("  holes             \(report.holes.isEmpty ? "none" : report.holes.prefix(20).map(String.init).joined(separator: ","))")
        if let lastAck {
            print("  last acknowledged \(lastAck)")
        }
        print("  verdict           \(verdict(report, lastAck: lastAck).line)")
        print("KILLTEST-REPORT-END")
        print("")
        fflush(stdout)
    }
}

// MARK: - Launch arguments

extension KillProbe {

    /// What a launch asked for. Parsed separately from acting on it so the parser can be tested
    /// against the exact inputs that have gone wrong before.
    public enum LaunchCommand: Equatable {
        /// No kill-test flag present: bring up the ordinary probe UI.
        case none
        case write(configurationIndex: Int, killAfterMs: Int, fresh: Bool, maxVisits: Int, throttleMicroseconds: UInt32)
        case inspect(lastAck: Int?)
        /// Something was supplied and could not be understood. Never a default.
        case invalid(String)
    }

    ///     --kill-test-write <configurationIndex> <killAfterMs> [--fresh] [--max-visits N] [--throttle-us N]
    ///     --kill-test-inspect [lastAcknowledgedSeq]
    ///
    /// Strict on purpose. The first version of the inspect path took `Int("1840\r")` — which is
    /// what a sequence number scraped out of `devicectl --console` looks like, CR and all — as
    /// nil, and treated the missing value as "no acknowledgement record supplied". That printed a
    /// FAIL for a journal that was perfectly intact. The write path kept the same shape for longer:
    /// an unreadable `--throttle-us` silently became 0, which is the value that makes a restart
    /// test meaningless, and nothing in the log said so.
    ///
    /// So: every numeric value is trimmed before parsing, and an argument that was supplied and
    /// cannot be understood is an error, not an absence. Absent optional flags take documented
    /// defaults; absent required values do not.
    public static func parseLaunchArguments(_ args: [String]) -> LaunchCommand {
        let writeIndex = args.firstIndex(of: "--kill-test-write")
        let inspectIndex = args.firstIndex(of: "--kill-test-inspect")

        switch (writeIndex, inspectIndex) {
        case (nil, nil):
            return .none
        case (.some, .some):
            return .invalid("--kill-test-write and --kill-test-inspect are mutually exclusive")
        case (.some(let i), nil):
            return parseWrite(args, at: i)
        case (nil, .some(let i)):
            return parseInspect(args, at: i)
        }
    }

    private static func value(_ args: [String], after index: Int) -> String? {
        guard args.count > index + 1 else { return nil }
        let raw = args[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.hasPrefix("--") ? nil : raw
    }

    private static func parseWrite(_ args: [String], at i: Int) -> LaunchCommand {
        guard let indexText = value(args, after: i) else {
            return .invalid("--kill-test-write needs a configuration index")
        }
        guard let index = Int(indexText) else {
            return .invalid("unparseable configuration index '\(args[i + 1])'")
        }
        guard Durability.candidates.indices.contains(index) else {
            return .invalid("configuration index \(index) is out of range 0...\(Durability.candidates.count - 1)")
        }
        guard let killText = value(args, after: i + 1) else {
            return .invalid("--kill-test-write needs a kill delay in milliseconds after the index")
        }
        guard let killAfterMs = Int(killText), killAfterMs > 0 else {
            return .invalid("unparseable kill delay '\(args[i + 2])'")
        }

        var maxVisits = 20_000
        if let j = args.firstIndex(of: "--max-visits") {
            guard let text = value(args, after: j) else { return .invalid("--max-visits needs a value") }
            guard let n = Int(text), n > 0 else { return .invalid("unparseable --max-visits '\(args[j + 1])'") }
            maxVisits = n
        }

        var throttle: UInt32 = 0
        if let j = args.firstIndex(of: "--throttle-us") {
            guard let text = value(args, after: j) else { return .invalid("--throttle-us needs a value") }
            guard let n = UInt32(text) else { return .invalid("unparseable --throttle-us '\(args[j + 1])'") }
            throttle = n
        }

        return .write(
            configurationIndex: index,
            killAfterMs: killAfterMs,
            fresh: args.contains("--fresh"),
            maxVisits: maxVisits,
            throttleMicroseconds: throttle
        )
    }

    private static func parseInspect(_ args: [String], at i: Int) -> LaunchCommand {
        guard args.count > i + 1, !args[i + 1].hasPrefix("--") else {
            return .inspect(lastAck: nil)
        }
        let raw = args[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(raw), parsed >= 0 else {
            return .invalid("unparseable acknowledgement '\(args[i + 1])'")
        }
        return .inspect(lastAck: parsed)
    }

    /// Runs a kill-test phase if the process was launched for one, otherwise returns and lets the
    /// normal UI come up.
    ///
    /// Driven by launch arguments rather than buttons so the whole test is scriptable. ADR-011
    /// requires this on every release candidate, and a test that needs someone to tap a phone in a
    /// particular order at a particular moment is a test that gets skipped under deadline — which
    /// is exactly the release where it would have mattered.
    public static func runFromLaunchArgumentsIfRequested() {
        switch parseLaunchArguments(CommandLine.arguments) {
        case .none:
            return

        case .invalid(let message):
            print("KILLTEST-ARGS-ERROR \(message)")
            fflush(stdout)
            exit(1)

        case .write(let index, let killAfterMs, let fresh, let maxVisits, let throttleUs):
            let configuration = Durability.candidates[index]
            // Echo what will actually run, so a log whose numbers look wrong can be checked against
            // the configuration that produced them instead of the one someone meant to pass.
            print("KILLTEST-CONFIG index=\(index) killAfterMs=\(killAfterMs) fresh=\(fresh) "
                  + "maxVisits=\(maxVisits) throttleUs=\(throttleUs)")
            fflush(stdout)
            // Throttling is what makes a restart test mean anything. `synchronous=NORMAL` does not
            // fsync, but the kernel flushes dirty pages on its own schedule anyway — within tens of
            // seconds. So a journal that stopped growing minutes ago is fully on disk by the time
            // anyone finishes a three-button restart gesture, and the restart then demonstrates
            // nothing: there was no unflushed data left to lose.
            //
            // Writing continuously at a modest rate keeps fresh, unflushed commits present at every
            // instant, so whenever the device goes down there is something at risk.
            //
            // On a background queue, and returning so the UI comes up. Running this loop inline
            // was killing the test: iOS gives an app about twenty seconds to finish launching, and
            // a write loop in App.init() never lets SwiftUI present a scene — so the watchdog sent
            // SIGKILL at roughly eighteen seconds every time, which read like the device restarting
            // and was nothing of the sort.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try writeUntilKilled(
                        configuration,
                        killAfterMs: killAfterMs,
                        fresh: fresh,
                        maxVisits: maxVisits,
                        throttleMicroseconds: throttleUs
                    )
                } catch {
                    print("KILLTEST-WRITE-ERROR \(error)")
                    fflush(stdout)
                    exit(1)
                }
            }
            keepScreenAwake()
            return

        case .inspect(let lastAck):
            do {
                let report = try inspect()
                printReport(report, lastAck: lastAck)
                // Same rule the console printed, so the exit code and the human-readable line
                // can never disagree again.
                exit(verdict(report, lastAck: lastAck).exitCode)
            } catch {
                print("KILLTEST-INSPECT-ERROR \(error)")
                fflush(stdout)
                exit(1)
            }
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif

extension KillProbe {
    /// Stops the screen locking during a restart test.
    ///
    /// iOS suspends a backgrounded app, and a suspended writer stops writing — which leaves the
    /// journal fully flushed again and the restart with nothing to catch. The test needs the app
    /// awake and committing right up to the moment the device goes down.
    static func keepScreenAwake() {
        #if canImport(UIKit) && !os(watchOS)
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        #endif
    }
}
