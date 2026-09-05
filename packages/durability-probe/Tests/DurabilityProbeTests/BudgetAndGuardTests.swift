import XCTest
import SQLite3
@testable import DurabilityProbe

/// `meetsBudget` is the "meets"/"EXCEEDS" column in every table ADR-006 records, and the green or
/// red label on the phone. It had one assertion, over samples where both P95 and P99 blew the
/// budget at once — so deleting either term of `p95 <= 20 && p99 <= 50` left the suite green.
/// Each case here fails under exactly one mutation of that line.
final class BudgetTests: XCTestCase {

    private func result(_ samples: [Double]) -> ProbeResult {
        ProbeResult(configuration: Durability.candidates[2], samplesMs: samples)
    }

    func testEntirelyWithinBudgetMeetsIt() {
        let r = result(Array(repeating: 1.0, count: 100))
        XCTAssertEqual(r.p95, 1.0)
        XCTAssertEqual(r.p99, 1.0)
        XCTAssertTrue(r.meetsBudget)
    }

    func testP99OverBudgetFailsEvenWhenP95IsFine() {
        // Nearest-rank P99 over 100 samples is the 99th, so two slow samples are needed to move it.
        let r = result(Array(repeating: 1.0, count: 98) + [200, 200])
        XCTAssertEqual(r.p95, 1.0)
        XCTAssertEqual(r.p99, 200.0)
        XCTAssertFalse(r.meetsBudget, "a phone that stalls a fifth of a second on one visit in a hundred does not meet the budget")
    }

    func testP95OverBudgetFailsEvenWhenP99IsFine() {
        let r = result(Array(repeating: 1.0, count: 94) + Array(repeating: 30.0, count: 5) + [40])
        XCTAssertEqual(r.p95, 30.0)
        XCTAssertEqual(r.p99, 30.0)
        XCTAssertFalse(r.meetsBudget, "P95 30 ms is over budget regardless of a P99 within it")
    }
}

/// The barrier guard, as run on the device. The XCTest version of this check never reaches the
/// phone — the app is built with no test bundle — so the printed report and the view carry it.
final class BarrierGuardTests: XCTestCase {

    private func relaxed(_ p50: Double) -> ProbeResult {
        ProbeResult(configuration: Durability.candidates[0], samplesMs: [p50])
    }
    private func barrier(_ p50: Double) -> ProbeResult {
        ProbeResult(configuration: Durability.candidates[2], samplesMs: [p50])
    }

    func testGuardHoldsWhenForcingTheBarrierIsSlower() throws {
        let g = try XCTUnwrap(Probe.barrierGuard([relaxed(0.02), barrier(0.70)]))
        XCTAssertTrue(g.holds)
        XCTAssertTrue(g.line.contains("THRO-PROBE-GUARD ok"))
    }

    func testGuardFailsWhenTheBarrierIsNotSlower() throws {
        let g = try XCTUnwrap(Probe.barrierGuard([relaxed(0.70), barrier(0.70)]))
        XCTAssertFalse(g.holds, "equal medians mean the pragmas did not take effect")
        XCTAssertTrue(g.line.contains("THRO-PROBE-GUARD FAILED"))
    }

    func testGuardIsAbsentWithoutBothConfigurations() {
        XCTAssertNil(Probe.barrierGuard([barrier(0.70)]))
        XCTAssertNil(Probe.barrierGuard([]))
    }

    func testGuardFindsTheConfigurationsRegardlessOfOrder() throws {
        let g = try XCTUnwrap(Probe.barrierGuard([barrier(0.65), relaxed(0.03), Durability.candidates[1], Durability.candidates[3]].compactMap {
            $0 as? ProbeResult
        }))
        XCTAssertEqual(g, Probe.BarrierGuard(relaxedP50: 0.03, barrierP50: 0.65))
    }
}

/// Pragmas are read back after being set, because `PRAGMA journal_mode` reports rather than
/// fails when it cannot switch, and `sqlite3_exec` with no callback discards the report.
final class PragmaReadBackTests: XCTestCase {

    func testEveryCandidateConfigurationIsInForceOnAFileDatabase() throws {
        for configuration in Durability.candidates {
            let path = NSTemporaryDirectory() + "thro-pragma-\(UUID().uuidString).sqlite"
            defer { KillProbe.removeJournal(at: path) }
            var db: OpaquePointer?
            XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
            guard let handle = db else { return XCTFail("no handle") }
            defer { sqlite3_close(handle) }
            XCTAssertNoThrow(try Probe.configure(handle, configuration), configuration.label)
            XCTAssertEqual(Probe.pragmaValue(handle, "journal_mode")?.lowercased(), configuration.journalMode.lowercased())
        }
    }

    func testARefusedJournalModeIsAnErrorNotASilentSuccess() throws {
        // An in-memory database cannot enter WAL mode. The pragma does not fail; it reports
        // "memory". Before the read-back, every pragma call here returned SQLITE_OK and the
        // measurement would have run under a configuration that was not in force.
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK)
        guard let handle = db else { return XCTFail("no handle") }
        defer { sqlite3_close(handle) }
        XCTAssertThrowsError(try Probe.configure(handle, Durability.candidates[2])) { error in
            XCTAssertTrue("\(error)".contains("journal_mode"), "\(error)")
            XCTAssertTrue("\(error)".contains("memory"), "the error must say what the database actually reports: \(error)")
        }
    }
}

final class EmptyResultTests: XCTestCase {
    func testNoSamplesIsNotWithinBudget() {
        let empty = ProbeResult(configuration: Durability.candidates[2], samplesMs: [])
        XCTAssertEqual(empty.p95, 0)
        XCTAssertFalse(empty.meetsBudget, "a result that measured nothing must not print 'meets'")
    }
}

final class CheckpointAndAttributionTests: XCTestCase {

    func testWalConfigurationsReportACheckpointCostAndRollbackDoesNot() throws {
        for configuration in Durability.candidates {
            let result = try Probe.measure(configuration, visits: 20)
            if configuration.journalMode.uppercased() == "WAL" {
                let ckpt = try XCTUnwrap(result.checkpointMs, configuration.label)
                XCTAssertGreaterThan(ckpt, 0, "a checkpoint that wrote twenty visits back cannot take zero time")
            } else {
                XCTAssertNil(result.checkpointMs, "the rollback journal has no WAL to checkpoint")
            }
        }
    }

    func testTheEnvironmentLineAttributesTheRun() {
        let line = Probe.environmentLine(visits: 200)
        XCTAssertTrue(line.hasPrefix("THRO-PROBE-ENV "))
        XCTAssertTrue(line.contains("visits=200"))
        XCTAssertTrue(line.contains("simulator="))
        XCTAssertFalse(line.contains("model=unknown"), line)
        XCTAssertFalse(line.contains("model= "), "the hardware identifier must not be empty: \(line)")
    }
}

final class PrintedReportTests: XCTestCase {
    /// Drives the same block the phone prints, so its shape is seen on every CI run rather than
    /// only on a device. (Output is inspected in the log; XCTest does not capture stdout.)
    func testThePrintedBlockCarriesAttributionCheckpointAndGuard() throws {
        var results: [ProbeResult] = []
        for configuration in Durability.candidates {
            results.append(try Probe.measure(configuration, visits: 20))
        }
        Probe.printReport(results)
        XCTAssertNotNil(Probe.barrierGuard(results))
        XCTAssertEqual(results.count, Durability.candidates.count)
    }
}
