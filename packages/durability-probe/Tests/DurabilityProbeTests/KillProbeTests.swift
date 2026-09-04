import XCTest
import SQLite3
@testable import DurabilityProbe

/// Tests for the half of the kill test that can run in a test process.
///
/// `KillProbe.writeUntilKilled` deliberately SIGKILLs its own process, so it cannot be exercised
/// here — running it under XCTest would kill the test runner, which is a fair description of what
/// it does and a poor test. The device-side procedure in
/// `docs/runbooks/DURABILITY_KILL_TEST.md` covers that half.
///
/// What is testable, and worth testing, is the adjudication: given a journal in some state, does
/// `inspect` describe it correctly? That logic decides whether a real kill test passes or fails, and
/// a bug in it would produce a confident wrong verdict — the worst available outcome.
final class KillProbeTests: XCTestCase {

    private var path: String { KillProbe.journalPath() }

    override func setUp() {
        super.setUp()
        KillProbe.removeJournal()
    }

    override func tearDown() {
        KillProbe.removeJournal()
        super.tearDown()
    }

    /// Builds a journal containing exactly `sequences`, bypassing the writer so that a state which
    /// only occurs after a crash can be constructed deliberately.
    private func seedJournal(_ sequences: [Int]) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        guard let handle = db else { return XCTFail("no handle") }
        defer { sqlite3_close(handle) }

        try Probe.exec(handle, """
            CREATE TABLE IF NOT EXISTS journal (
              device_seq INTEGER PRIMARY KEY,
              match_id   TEXT NOT NULL,
              visit_total INTEGER NOT NULL,
              occurred_at TEXT NOT NULL
            );
            """)
        for seq in sequences {
            try Probe.exec(handle, """
                INSERT INTO journal (device_seq, match_id, visit_total, occurred_at)
                VALUES (\(seq), 'm', 60, '2026-09-04T00:00:00Z');
                """)
        }
    }

    func testIntactJournalIsContiguousAndHealthy() throws {
        try seedJournal(Array(1...50))

        let report = try KillProbe.inspect()

        XCTAssertTrue(report.opened)
        XCTAssertEqual(report.integrity, "ok")
        XCTAssertEqual(report.maxSeq, 50)
        XCTAssertEqual(report.rowCount, 50)
        XCTAssertEqual(report.holes, [])
        XCTAssertTrue(report.contiguous)
        XCTAssertTrue(report.healthy)
    }

    /// The failure this whole test exists to catch: a write that was acknowledged and is not there.
    func testHoleInTheSequenceIsReported() throws {
        try seedJournal([1, 2, 3, 5, 6])

        let report = try KillProbe.inspect()

        XCTAssertEqual(report.maxSeq, 6)
        XCTAssertEqual(report.rowCount, 5)
        XCTAssertEqual(report.holes, [4], "a missing acknowledged visit must be named, not just counted")
        XCTAssertFalse(report.contiguous)
        XCTAssertFalse(report.healthy)
    }

    /// A journal that simply stops early is the *expected* result of a kill: writes after the kill
    /// never happened, so they were never acknowledged and are not losses.
    func testTruncatedJournalIsStillContiguous() throws {
        try seedJournal(Array(1...12))

        let report = try KillProbe.inspect()

        XCTAssertTrue(report.contiguous, "stopping early is not the same as losing something")
        XCTAssertTrue(report.healthy)
    }

    /// The verdict is one-directional on purpose. SIGKILL discards buffered stdout, so a write can
    /// land without its acknowledgement reaching the console. More in the journal than we saw
    /// acknowledged is normal; less is the failure.
    func testJournalAheadOfTheAcknowledgementRecordIsNotAFailure() throws {
        try seedJournal(Array(1...100))

        let report = try KillProbe.inspect()

        XCTAssertGreaterThanOrEqual(report.maxSeq, 97, "journal may legitimately lead the console record")
        XCTAssertTrue(report.healthy)
    }

    func testEmptyJournalReportsNothingRatherThanCrashing() throws {
        let report = try KillProbe.inspect()

        XCTAssertEqual(report.maxSeq, 0)
        XCTAssertEqual(report.rowCount, 0)
        XCTAssertEqual(report.holes, [])
    }
}
