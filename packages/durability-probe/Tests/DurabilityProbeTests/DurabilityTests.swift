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

    /// Runs before the report (XCTest orders by name) so that a failure in the measurement itself
    /// is distinguishable from a failure in reporting it.
    func testOneDurableWriteLands() throws {
        let result = try Probe.measure(Durability.candidates[2], visits: 5)
        XCTAssertEqual(result.samplesMs.count, 5, "a sample per committed visit")
        XCTAssertTrue(result.samplesMs.allSatisfy { $0 > 0 }, "a durable commit cannot take zero time")
        // Probe.measure counts the rows before returning, so reaching here means they landed.
    }

    func testReportDurabilityLatency() throws {
        var results: [ProbeResult] = []
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
        print("  " + pad("configuration", 58) + padLeft("P50", 9) + padLeft("P95", 9)
              + padLeft("P99", 9) + padLeft("worst", 9) + "   budget")
        for r in results {
            print("  " + pad(r.configuration.label, 58)
                  + padLeft(fixed(r.p50), 9) + padLeft(fixed(r.p95), 9)
                  + padLeft(fixed(r.p99), 9) + padLeft(fixed(r.worst), 9)
                  + "   " + (r.meetsBudget ? "meets" : "EXCEEDS"))
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
        print("  relaxed P50 \(fixed(relaxed.p50)) ms vs full+fullfsync P50 \(fixed(strongest.p50)) ms")
        XCTAssertGreaterThan(
            strongest.p50, relaxed.p50,
            "forcing a real barrier was not slower than not forcing one — the pragmas did not take, "
            + "so every number this probe reports is meaningless"
        )
    }

    func testPercentilesAreSamplesThatActuallyOccurred() {
        // Nearest-rank, not interpolation: a reported P99 must be a latency something really took.
        let m = ProbeResult(
            configuration: Durability.candidates[0],
            samplesMs: [1, 2, 3, 4, 5, 6, 7, 8, 9, 100]
        )
        XCTAssertEqual(m.p50, 5)
        XCTAssertEqual(m.p95, 100)
        XCTAssertEqual(m.p99, 100)
        XCTAssertEqual(m.worst, 100)
        XCTAssertFalse(m.meetsBudget, "a 100 ms P99 must not read as meeting a 50 ms budget")
    }

    // Column alignment done by hand rather than with String(format:).
    //
    // `String(format: "%-58s", someSwiftString)` is what this file used to do, and it is a crash,
    // not a cosmetic mistake: %s takes a C `char *`, a Swift String reaches the formatter as a
    // bridged NSString object pointer, and short literals are tagged pointers whose tag bits make
    // them invalid addresses. Dereferencing one segfaults the whole test process before a single
    // number is printed. %@ is the correct specifier for a String; not needing one at all is
    // better still.
    private func pad(_ value: String, _ width: Int) -> String {
        value.count >= width
            ? String(value.prefix(width))
            : value + String(repeating: " ", count: width - value.count)
    }

    private func padLeft(_ value: String, _ width: Int) -> String {
        value.count >= width
            ? String(value.suffix(width))
            : String(repeating: " ", count: width - value.count) + value
    }

    /// `%f` with a Double is a correct use of String(format:) — the argument really is a C double.
    private func fixed(_ value: Double) -> String { String(format: "%.2f", value) }
}
