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
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: journalPath() + suffix)
        }
    }

    // MARK: - Phase one: write until killed

    /// Writes visits under `configuration` and terminates the process partway through.
    ///
    /// Every acknowledged sequence number is printed and the stream flushed immediately, because
    /// SIGKILL discards whatever is still sitting in the stdout buffer. An acknowledgement we fail
    /// to record makes the test under-claim rather than over-claim — the safe direction — but it
    /// also makes it blunt, and the flush costs nothing next to a storage barrier.
    ///
    /// SIGKILL rather than `exit()` on purpose. `exit()` runs atexit handlers and flushes buffers,
    /// which is precisely what a crash does not do; it would quietly test the happy path. SIGKILL
    /// cannot be caught or ignored, so the process stops between two instructions with no
    /// opportunity to tidy up — which is the event being simulated.
    ///
    /// The kill fires from a background thread after `killAfterMs`, so it lands wherever the writer
    /// happens to be, usually inside a transaction. That is the case worth testing: a torn write,
    /// not a clean stop between two of them.
    public static func writeUntilKilled(
        _ configuration: Durability,
        killAfterMs: Int,
        fresh: Bool
    ) throws {
        if fresh { removeJournal() }

        let path = journalPath()
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let handle = db else {
            if let leaked = db { sqlite3_close(leaked) }
            throw ProbeError.sqlite("could not open \(path)")
        }

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
        if sqlite3_prepare_v2(handle, "SELECT IFNULL(MAX(device_seq), 0) FROM journal;", -1, &countStmt, nil) == SQLITE_OK,
           let cs = countStmt {
            if sqlite3_step(cs) == SQLITE_ROW { startSeq = Int(sqlite3_column_int64(cs, 0)) }
            sqlite3_finalize(cs)
        }

        let deadline = DispatchTime.now() + .milliseconds(killAfterMs)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: deadline) {
            print("KILLTEST-KILLING-NOW")
            fflush(stdout)
            kill(getpid(), SIGKILL)
        }

        var statement: OpaquePointer?
        let insert = """
            INSERT INTO journal (device_seq, match_id, visit_total, occurred_at)
            VALUES (?, ?, ?, ?);
            """
        guard sqlite3_prepare_v2(handle, insert, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw ProbeError.sqlite("prepare failed: \(String(cString: sqlite3_errmsg(handle)))")
        }

        let matchId = UUID().uuidString
        let occurredAt = ISO8601DateFormatter().string(from: Date())

        // Same SQLITE_STATIC discipline as Probe: bind against buffers whose lifetime we control,
        // never a bridged Swift String, and never a bit-cast SQLITE_TRANSIENT.
        matchId.withCString { matchC in
            occurredAt.withCString { occurredC in
                var seq = startSeq
                while true {
                    seq += 1
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                    sqlite3_bind_int64(stmt, 1, sqlite3_int64(seq))
                    sqlite3_bind_text(stmt, 2, matchC, -1, nil)
                    sqlite3_bind_int(stmt, 3, Int32(60 + (seq % 41)))
                    sqlite3_bind_text(stmt, 4, occurredC, -1, nil)

                    if sqlite3_step(stmt) != SQLITE_DONE {
                        print("KILLTEST-WRITE-ERROR \(String(cString: sqlite3_errmsg(handle)))")
                        fflush(stdout)
                        return
                    }
                    // Acknowledged only now: sqlite3_step has returned, so the durable write this
                    // configuration promises has completed. ADR-006's rule is that acknowledgement
                    // follows the flush, and this print is the acknowledgement.
                    print("KILLTEST-ACK \(seq)")
                    fflush(stdout)
                }
            }
        }

        sqlite3_finalize(stmt)
        sqlite3_close(handle)
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

        public var contiguous: Bool { holes.isEmpty && rowCount == maxSeq }
        public var healthy: Bool { opened && integrity == "ok" && contiguous }
    }

    /// Reopens the journal after the kill and reports what is actually in it.
    public static func inspect() throws -> Report {
        let path = journalPath()
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let handle = db else {
            if let leaked = db { sqlite3_close(leaked) }
            return Report(opened: false, integrity: "could not open", maxSeq: 0, rowCount: 0, holes: [])
        }
        defer { sqlite3_close(handle) }

        // integrity_check is what distinguishes "we lost the tail" from "the file is damaged".
        // A torn write that corrupts the b-tree is a different and worse failure than one that
        // simply did not land, and the report should not blur them.
        var integrity = "unknown"
        var integrityStmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, "PRAGMA integrity_check;", -1, &integrityStmt, nil) == SQLITE_OK,
           let istmt = integrityStmt {
            if sqlite3_step(istmt) == SQLITE_ROW, let text = sqlite3_column_text(istmt, 0) {
                integrity = String(cString: text)
            }
            sqlite3_finalize(istmt)
        }

        var maxSeq = 0
        var rowCount = 0
        var aggStmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, "SELECT IFNULL(MAX(device_seq), 0), COUNT(*) FROM journal;", -1, &aggStmt, nil) == SQLITE_OK,
           let astmt = aggStmt {
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

        return Report(opened: true, integrity: integrity, maxSeq: maxSeq, rowCount: rowCount, holes: holes)
    }

    /// Prints the surviving state, and the verdict against a known last acknowledgement.
    ///
    /// `lastAck` comes from the console record of the killed run. The invariant is one-directional:
    /// the journal may legitimately hold *more* than we saw acknowledged, because the kill can
    /// discard a buffered acknowledgement for a write that did land. It may never hold less.
    public static func printReport(_ report: Report, lastAck: Int?) {
        print("")
        print("KILLTEST-REPORT-BEGIN")
        print("  opened            \(report.opened)")
        print("  integrity_check   \(report.integrity)")
        print("  max device_seq    \(report.maxSeq)")
        print("  rows              \(report.rowCount)")
        print("  holes             \(report.holes.isEmpty ? "none" : report.holes.prefix(20).map(String.init).joined(separator: ","))")
        if let lastAck {
            let lost = lastAck - report.maxSeq
            print("  last acknowledged \(lastAck)")
            print("  verdict           " + (lost <= 0
                ? "PASS — nothing acknowledged was lost"
                : "FAIL — \(lost) acknowledged visit(s) missing"))
        } else {
            print("  verdict           " + (report.healthy
                ? "journal intact and contiguous (no acknowledgement record supplied)"
                : "PROBLEM — see integrity_check and holes"))
        }
        print("KILLTEST-REPORT-END")
        print("")
        fflush(stdout)
    }
}

extension KillProbe {

    /// Runs a kill-test phase if the process was launched for one, otherwise returns and lets the
    /// normal UI come up.
    ///
    /// Driven by launch arguments rather than buttons so the whole test is scriptable. ADR-011
    /// requires this on every release candidate, and a test that needs someone to tap a phone in a
    /// particular order at a particular moment is a test that gets skipped under deadline — which
    /// is exactly the release where it would have mattered.
    ///
    ///     --kill-test-write <configurationIndex> <killAfterMs> [--fresh]
    ///     --kill-test-inspect [lastAcknowledgedSeq]
    public static func runFromLaunchArgumentsIfRequested() {
        let args = CommandLine.arguments

        if let i = args.firstIndex(of: "--kill-test-write") {
            let index = args.count > i + 1 ? Int(args[i + 1]) ?? 2 : 2
            let killAfterMs = args.count > i + 2 ? Int(args[i + 2]) ?? 1500 : 1500
            let configuration = Durability.candidates[
                min(max(index, 0), Durability.candidates.count - 1)
            ]
            do {
                try writeUntilKilled(
                    configuration,
                    killAfterMs: killAfterMs,
                    fresh: args.contains("--fresh")
                )
            } catch {
                print("KILLTEST-WRITE-ERROR \(error)")
                fflush(stdout)
                exit(1)
            }
            // writeUntilKilled only returns if the writer stopped early, which is itself a result
            // worth surfacing rather than falling through into the UI.
            exit(1)
        }

        if let i = args.firstIndex(of: "--kill-test-inspect") {
            // Trim before parsing. `devicectl --console` relays the device's stdout with CRLF line
            // endings, so a sequence number scraped out of that log arrives here as "1840\r" and
            // Int() returns nil for it.
            //
            // Silently treating that as "no acknowledgement record supplied" is how this reported a
            // FAIL on a run whose journal was in fact intact — a false failure on a durability test,
            // which is the one direction of error that must never be quiet. An argument that was
            // supplied and cannot be understood is an error, not an absence.
            var lastAck: Int? = nil
            if args.count > i + 1, !args[i + 1].hasPrefix("--") {
                let raw = args[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let parsed = Int(raw) else {
                    print("KILLTEST-INSPECT-ERROR unparseable acknowledgement '\(args[i + 1])'")
                    fflush(stdout)
                    exit(1)
                }
                lastAck = parsed
            }
            do {
                let report = try inspect()
                printReport(report, lastAck: lastAck)
                exit(report.healthy && (lastAck.map { $0 <= report.maxSeq } ?? true) ? 0 : 2)
            } catch {
                print("KILLTEST-INSPECT-ERROR \(error)")
                fflush(stdout)
                exit(1)
            }
        }
    }
}
