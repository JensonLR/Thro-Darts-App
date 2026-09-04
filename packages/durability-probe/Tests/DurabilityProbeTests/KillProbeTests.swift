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

    // MARK: - The pass rule
    //
    // These exercise `KillProbe.verdict` rather than `inspect`. The test that used to sit here was
    // named for the one-directional invariant but never supplied a `lastAck`, so it asserted only
    // that a 100-row journal reports maxSeq >= 97 — which testIntactJournalIsContiguousAndHealthy
    // already covers exactly. The rule that actually decides pass or fail had no test at all, and
    // that is the rule a bug in produces a confident wrong verdict.

    /// The failure this whole apparatus exists to detect: the console recorded an acknowledgement
    /// the journal does not contain.
    func testAcknowledgementBeyondTheJournalFails() throws {
        try seedJournal(Array(1...95))

        let report = try KillProbe.inspect()
        let verdict = KillProbe.verdict(report, lastAck: 100)

        XCTAssertFalse(verdict.isPass, "five acknowledged visits are missing and the verdict passed")
        XCTAssertTrue(verdict.line.contains("5 acknowledged"), "got: \(verdict.line)")
    }

    /// One-directional on purpose: SIGKILL discards buffered stdout, so a write can land without
    /// its acknowledgement reaching the console. More in the journal than we saw acknowledged is
    /// normal; less is the failure.
    func testJournalAheadOfTheAcknowledgementRecordPasses() throws {
        try seedJournal(Array(1...100))

        let report = try KillProbe.inspect()
        XCTAssertTrue(
            KillProbe.verdict(report, lastAck: 95).isPass,
            "the journal may lead the console record — that is a discarded print, not a lost write"
        )
    }

    /// The regression this pair of tests was written for.
    ///
    /// A hole below maxSeq is a lost acknowledgement — the writer reached a higher sequence, so the
    /// missing one had already returned from sqlite3_step. The printed verdict used to compare only
    /// the tail against lastAck, so this case printed "PASS — nothing acknowledged was lost" while
    /// the process exited 2. The console said pass; the truth was a hole.
    func testHoleFailsEvenWhenTheTailSatisfiesTheAcknowledgement() throws {
        try seedJournal(Array(1...50) + Array(52...100))

        let report = try KillProbe.inspect()
        XCTAssertEqual(report.holes, [51])

        let verdict = KillProbe.verdict(report, lastAck: 100)
        XCTAssertFalse(verdict.isPass, "seq 51 was acknowledged and is gone, and the verdict passed")
        XCTAssertTrue(verdict.line.contains("51"), "the missing sequence must be named, got: \(verdict.line)")
    }

    func testIntactJournalPassesWithAndWithoutAnAcknowledgementRecord() throws {
        try seedJournal(Array(1...40))
        let report = try KillProbe.inspect()

        XCTAssertTrue(KillProbe.verdict(report, lastAck: 40).isPass)
        XCTAssertTrue(KillProbe.verdict(report, lastAck: nil).isPass)
    }

    /// Corruption is a different and worse failure than a short journal, and must not read as a
    /// missing acknowledgement.
    func testFailedIntegrityCheckFailsRegardlessOfSequences() {
        let corrupt = KillProbe.Report(
            opened: true, integrity: "row 3 missing from index", maxSeq: 100, rowCount: 100, holes: []
        )

        let verdict = KillProbe.verdict(corrupt, lastAck: 100)

        XCTAssertFalse(verdict.isPass, "a corrupt journal passed because its sequence was contiguous")
        XCTAssertTrue(verdict.line.contains("integrity_check"), "got: \(verdict.line)")
    }

    func testEmptyJournalReportsNothingRatherThanCrashing() throws {
        let report = try KillProbe.inspect()

        XCTAssertEqual(report.maxSeq, 0)
        XCTAssertEqual(report.rowCount, 0)
        XCTAssertEqual(report.holes, [])
    }
}
