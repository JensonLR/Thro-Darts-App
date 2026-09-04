import XCTest
@testable import DurabilityProbe

/// The measurement ADR-006 requires before the client architecture is fixed.
///
/// This is deliberately a *report*, not a pass/fail gate on CI hardware. A CI runner's disk says
/// nothing about a five-year-old phone in a pub, and asserting a budget here would manufacture
/// confidence from the wrong machine. The assertion that does fire is the one that holds
/// everywhere: the strongest configuration must not be faster than the weakest, because if it is,
/// the barrier is not happening and every number is meaningless.
final class DurabilityTests: XCTestCase {

    func testReportDurabilityLatency() throws {
        var results: [Measurement] = []
        for configuration in Durability.candidates {
            results.append(try Probe.measure(configuration, visits: 200))
        }

        print("")
        print("  THRØ durability probe — one durable transaction per visit, 200 visits")
        print("  budget (LATENCY_BUDGETS.md): P95 ≤ 20 ms, P99 ≤ 50 ms")
        #if os(iOS)
        print("  running on: iOS — this is the number that counts")
        #else
        print("  running on: macOS — INDICATIVE ONLY. ADR-006 requires both reference devices,")
        print("              because fsync on Apple platforms behaves differently per device class.")
        #endif
        print("")
        print(String(format: "  %-58s %8s %8s %8s %8s   %s",
                     "configuration", "P50", "P95", "P99", "worst", "budget"))
        for r in results {
            print(String(format: "  %-58s %8.2f %8.2f %8.2f %8.2f   %s",
                         String(r.configuration.label.prefix(58)),
                         r.p50, r.p95, r.p99, r.worst,
                         r.meetsBudget ? "meets" : "EXCEEDS"))
        }
        print("")
        print("  If the strongest configuration exceeds the budget, ADR-006 is explicit about which")
        print("  side gives way: the durability rule wins and the budget is restated. The fallback")
        print("  is a raw append-only write-ahead file with the database demoted to a projection —")
        print("  a second storage engine on both clients, not a tweak.")
        print("")

        XCTAssertEqual(results.count, Durability.candidates.count)
        XCTAssertTrue(results.allSatisfy { !$0.samplesMs.isEmpty }, "a configuration produced no samples")
    }

    /// Guards the probe itself. If a real storage barrier is being issued, forcing it cannot be
    /// free — so a strongest-configuration median at or below the relaxed one means the pragmas did
    /// not take effect and the whole measurement is worthless.
    func testTheBarrierIsActuallyHappening() throws {
        let relaxed = try Probe.measure(Durability.candidates[0], visits: 100)
        let strongest = try Probe.measure(Durability.candidates[2], visits: 100)
        print(String(format: "  relaxed P50 %.3f ms vs full+fullfsync P50 %.3f ms",
                     relaxed.p50, strongest.p50))
        XCTAssertGreaterThan(
            strongest.p50, relaxed.p50,
            "forcing a real barrier was not slower than not forcing one — the pragmas did not take, "
            + "so every number this probe reports is meaningless"
        )
    }

    func testPercentilesAreSamplesThatActuallyOccurred() {
        // Nearest-rank, not interpolation: a reported P99 must be a latency something really took.
        let m = Measurement(
            configuration: Durability.candidates[0],
            samplesMs: [1, 2, 3, 4, 5, 6, 7, 8, 9, 100]
        )
        XCTAssertEqual(m.p50, 5)
        XCTAssertEqual(m.p95, 100)
        XCTAssertEqual(m.p99, 100)
        XCTAssertEqual(m.worst, 100)
        XCTAssertFalse(m.meetsBudget, "a 100 ms P99 must not read as meeting a 50 ms budget")
    }
}
