import XCTest
import SQLite3
@testable import DurabilityProbe

/// The launch-argument parser, tested against the inputs that have actually gone wrong.
///
/// It reads nothing from `CommandLine` itself, so every case here is a plain array — including the
/// one with a carriage return in it, which is what a value scraped out of `devicectl --console`
/// looks like and which the first version silently turned into "no acknowledgement supplied".
final class KillProbeLaunchArgumentTests: XCTestCase {

    func testNoFlagsMeansTheOrdinaryProbeUI() {
        XCTAssertEqual(KillProbe.parseLaunchArguments(["ThroProbe"]), .none)
    }

    func testInspectAcceptsACarriageReturnedAcknowledgement() {
        XCTAssertEqual(
            KillProbe.parseLaunchArguments(["ThroProbe", "--kill-test-inspect", "1840\r"]),
            .inspect(lastAck: 1840),
            "CRLF from devicectl must be trimmed, not treated as an absent value"
        )
    }

    func testInspectWithoutAValueMeansNoRecordSupplied() {
        XCTAssertEqual(KillProbe.parseLaunchArguments(["ThroProbe", "--kill-test-inspect"]), .inspect(lastAck: nil))
    }

    func testInspectRejectsAnUnreadableAcknowledgement() {
        guard case .invalid = KillProbe.parseLaunchArguments(["ThroProbe", "--kill-test-inspect", "18x40"]) else {
            return XCTFail("an acknowledgement that was supplied and cannot be read is an error, not an absence")
        }
    }

    func testWriteRequiresBothAnIndexAndADelay() {
        guard case .invalid = KillProbe.parseLaunchArguments(["ThroProbe", "--kill-test-write"]) else {
            return XCTFail("no index must not default to the real barrier")
        }
        guard case .invalid = KillProbe.parseLaunchArguments(["ThroProbe", "--kill-test-write", "2"]) else {
            return XCTFail("no delay must not default to 1500")
        }
    }

    func testWriteRejectsAnOutOfRangeIndexRatherThanClamping() {
        guard case .invalid = KillProbe.parseLaunchArguments(["ThroProbe", "--kill-test-write", "7", "1500"]) else {
            return XCTFail("index 7 used to be clamped to 3 without a word — a run under the wrong configuration")
        }
    }

    func testWriteParsesTheFullForm() {
        XCTAssertEqual(
            KillProbe.parseLaunchArguments([
                "ThroProbe", "--kill-test-write", "2", "1500", "--fresh",
                "--max-visits", "40000", "--throttle-us", "8000",
            ]),
            .write(configurationIndex: 2, killAfterMs: 1500, fresh: true, maxVisits: 40000, throttleMicroseconds: 8000)
        )
    }

    func testOnlyAbsentOptionalFlagsTakeDefaults() {
        XCTAssertEqual(
            KillProbe.parseLaunchArguments(["ThroProbe", "--kill-test-write", "0", "3600000"]),
            .write(configurationIndex: 0, killAfterMs: 3_600_000, fresh: false, maxVisits: 20_000, throttleMicroseconds: 0)
        )
    }

    func testAThrottleWithUnitsIsAnErrorNotZero() {
        // Zero is the one value that makes a restart test meaningless: the writer runs flat out,
        // hits its cap in seconds, and the kernel has flushed everything before the operator has
        // finished reading the instructions. It must never be arrived at silently.
        guard case .invalid = KillProbe.parseLaunchArguments(["ThroProbe", "--kill-test-write", "0", "1000", "--throttle-us", "8ms"]) else {
            return XCTFail("'8ms' became a throttle of 0")
        }
    }

    func testAFlagWithoutAValueIsAnError() {
        guard case .invalid = KillProbe.parseLaunchArguments(["ThroProbe", "--kill-test-write", "0", "1000", "--throttle-us"]) else {
            return XCTFail("trailing --throttle-us must not default")
        }
        guard case .invalid = KillProbe.parseLaunchArguments(["ThroProbe", "--kill-test-write", "0", "1000", "--max-visits", "--fresh"]) else {
            return XCTFail("--max-visits followed by another flag has no value")
        }
    }

    func testWriteAndInspectTogetherIsAnError() {
        guard case .invalid = KillProbe.parseLaunchArguments(["ThroProbe", "--kill-test-write", "0", "1000", "--kill-test-inspect"]) else {
            return XCTFail("two phases in one launch is a mistake, not a choice")
        }
    }
}

/// The write loop's terminal states. `writeUntilKilled` itself cannot run under XCTest — it
/// SIGKILLs the process — but the loop it wraps can, and its two ways of stopping are exactly the
/// two conditions that make a run void.
final class KillProbeWriterTests: XCTestCase {

    private var path: String { KillProbe.journalPath() }
    private let relaxed = Durability.candidates[0]

    override func setUp() { super.setUp(); KillProbe.removeJournal() }
    override func tearDown() { KillProbe.removeJournal(); super.tearDown() }

    func testWriterStopsAtTheCapAndReportsTheLastSequence() throws {
        let reached = try KillProbe.writeVisits(at: path, relaxed, maxVisits: 25, throttleMicroseconds: 0)
        XCTAssertEqual(reached, 25)

        let report = try KillProbe.inspect(at: path)
        XCTAssertTrue(report.tableFound)
        XCTAssertEqual(report.rowCount, 25)
        XCTAssertEqual(report.maxSeq, 25)
        XCTAssertTrue(report.contiguous)
        XCTAssertEqual(report.journalMode.lowercased(), "wal")
    }

    func testWriterResumesAfterAnExistingJournal() throws {
        try KillProbe.writeVisits(at: path, relaxed, maxVisits: 5, throttleMicroseconds: 0)
        let reached = try KillProbe.writeVisits(at: path, relaxed, maxVisits: 3, throttleMicroseconds: 0)
        XCTAssertEqual(reached, 8, "a second pass extends the journal rather than colliding on the primary key")

        let report = try KillProbe.inspect(at: path)
        XCTAssertEqual(report.rowCount, 8)
        XCTAssertTrue(report.contiguous)
    }

    /// The failure path used to `return` from the loop, close the handle cleanly — checkpointing
    /// the WAL and flushing everything the configuration under test had left in the kernel — and
    /// let `writeUntilKilled` return normally, so nothing upstream noticed and the scheduled kill
    /// landed on a journal that had been idle for most of a minute. That adjudicates as a pass.
    func testAFailedWriteThrowsInsteadOfReturningNormally() throws {
        try KillProbe.writeVisits(at: path, relaxed, maxVisits: 2, throttleMicroseconds: 0)

        // A second connection holding the write lock makes the writer's next INSERT fail with
        // SQLITE_BUSY — a real step failure, not a contrived one.
        var lock: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &lock), SQLITE_OK)
        guard let lockHandle = lock else { return XCTFail("no lock handle") }
        defer { sqlite3_close(lockHandle) }
        try Probe.exec(lockHandle, "BEGIN IMMEDIATE;")

        XCTAssertThrowsError(try KillProbe.writeVisits(at: path, relaxed, maxVisits: 10, throttleMicroseconds: 0)) { error in
            let text = "\(error)".lowercased()
            XCTAssertTrue(text.contains("locked") || text.contains("busy"), "unexpected error: \(error)")
        }

        try Probe.exec(lockHandle, "ROLLBACK;")
    }

    /// Bug #2 of the session, as a test. In WAL mode commits go to the sidecar first; the main
    /// file only catches up at a checkpoint. A writer that is killed never checkpoints, so a copy of
    /// the main file taken on its own is missing everything since the last checkpoint — here, the
    /// table itself. Adjudicating that copy gives a confident answer about a different journal.
    func testAdjudicatingWithoutTheWalSidecarDescribesADifferentJournal() throws {
        // Hold the writer's connection open so nothing is checkpointed, and disable the
        // automatic checkpoint so the WAL keeps everything.
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        guard let handle = db else { return XCTFail("no handle") }
        defer { sqlite3_close(handle) }
        try Probe.exec(handle, "PRAGMA journal_mode = WAL;")
        try Probe.exec(handle, "PRAGMA wal_autocheckpoint = 0;")
        try Probe.exec(handle, """
            CREATE TABLE journal (
              device_seq INTEGER PRIMARY KEY, match_id TEXT NOT NULL,
              visit_total INTEGER NOT NULL, occurred_at TEXT NOT NULL);
            """)
        for seq in 1...50 {
            try Probe.exec(handle, "INSERT INTO journal VALUES (\(seq), 'm', 60, '2026-09-04T00:00:00Z');")
        }
        XCTAssertTrue(KillProbe.hasWalSidecar(at: path), "with checkpointing off, the commits are in the sidecar")

        // The pull that copies only the main file.
        let copy = path + ".main-only"
        defer { KillProbe.removeJournal(at: copy) }
        try? FileManager.default.removeItem(atPath: copy)
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        XCTAssertFalse(KillProbe.hasWalSidecar(at: copy), "the copy has no sidecar — that is the mistake")

        let partial = try KillProbe.inspect(at: copy)
        XCTAssertLessThan(partial.rowCount, 50, "the main file alone is behind the journal")
        XCTAssertFalse(KillProbe.verdict(partial, lastAck: 50).isPass,
                       "against the console record this copy looks like data loss; it is an incomplete pull")

        // And with the sidecar copied too, the same journal is intact.
        let full = path + ".full"
        defer { KillProbe.removeJournal(at: full) }
        try? FileManager.default.removeItem(atPath: full)
        try FileManager.default.copyItem(atPath: path, toPath: full)
        try FileManager.default.copyItem(atPath: path + "-wal", toPath: full + "-wal")
        let complete = try KillProbe.inspect(at: full)
        XCTAssertEqual(complete.rowCount, 50)
        XCTAssertTrue(KillProbe.verdict(complete, lastAck: 50).isPass)
    }

    func testRollbackJournalConfigurationReportsItsMode() throws {
        try KillProbe.writeVisits(at: path, Durability.candidates[3], maxVisits: 3, throttleMicroseconds: 0)
        let report = try KillProbe.inspect(at: path)
        XCTAssertEqual(report.journalMode.lowercased(), "delete",
                       "the adjudicator uses journal_mode to know whether a missing -wal sidecar matters")
    }
}

/// "Nothing was measured" must never come out as "nothing was lost".
final class KillProbeVoidVerdictTests: XCTestCase {

    private var path: String { KillProbe.journalPath() }

    override func setUp() { super.setUp(); KillProbe.removeJournal() }
    override func tearDown() { KillProbe.removeJournal(); super.tearDown() }

    /// An empty database file with no `journal` table — what `sqlite3_open` leaves behind when
    /// the journal was never there.
    private func createEmptyDatabase() {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        if let db { sqlite3_close(db) }
    }

    func testAMissingTableIsReportedRatherThanDefaultedToZeroRows() throws {
        createEmptyDatabase()
        let report = try KillProbe.inspect(at: path)

        XCTAssertTrue(report.opened)
        XCTAssertFalse(report.tableFound)
        XCTAssertFalse(report.healthy)
        guard case .void = KillProbe.verdict(report, lastAck: nil) else {
            return XCTFail("an absent journal table is nothing to adjudicate, got \(KillProbe.verdict(report, lastAck: nil))")
        }
    }

    func testAMissingTableWithAcknowledgementsOnRecordIsALoss() throws {
        createEmptyDatabase()
        let report = try KillProbe.inspect(at: path)

        let verdict = KillProbe.verdict(report, lastAck: 10)
        guard case .fail = verdict else {
            return XCTFail("ten visits were acknowledged and the journal is gone; that is a loss, got \(verdict)")
        }
        XCTAssertEqual(verdict.exitCode, 2)
    }

    func testAnEmptyTableWithNothingAcknowledgedIsVoid() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        guard let handle = db else { return XCTFail("no handle") }
        try Probe.exec(handle, """
            CREATE TABLE journal (
              device_seq INTEGER PRIMARY KEY, match_id TEXT NOT NULL,
              visit_total INTEGER NOT NULL, occurred_at TEXT NOT NULL);
            """)
        sqlite3_close(handle)

        let report = try KillProbe.inspect(at: path)
        XCTAssertTrue(report.tableFound)
        XCTAssertEqual(report.rowCount, 0)

        for lastAck in [nil, 0] as [Int?] {
            let verdict = KillProbe.verdict(report, lastAck: lastAck)
            guard case .void = verdict else {
                return XCTFail("zero rows and nothing acknowledged has no verdict to give, got \(verdict)")
            }
            XCTAssertEqual(verdict.exitCode, 3)
            XCTAssertFalse(verdict.isPass)
        }
    }

    func testExitCodesAndLinesAreDistinctPerOutcome() {
        XCTAssertEqual(KillProbe.Verdict.pass("x").exitCode, 0)
        XCTAssertEqual(KillProbe.Verdict.fail("x").exitCode, 2)
        XCTAssertEqual(KillProbe.Verdict.void("x").exitCode, 3)
        XCTAssertTrue(KillProbe.Verdict.pass("x").line.hasPrefix("PASS — "))
        XCTAssertTrue(KillProbe.Verdict.fail("x").line.hasPrefix("FAIL — "))
        XCTAssertTrue(KillProbe.Verdict.void("x").line.hasPrefix("VOID — "))
        XCTAssertFalse(KillProbe.Verdict.void("x").isPass)
    }
}
