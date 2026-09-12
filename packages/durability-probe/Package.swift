// swift-tools-version:5.9
import PackageDescription

// ADR-006 requires the durability latency of a visit write to be MEASURED on both reference
// devices before the client architecture is fixed. This package is that measurement and nothing
// else — it writes synthetic visits under each candidate SQLite configuration and reports the
// distribution against the budget in LATENCY_BUDGETS.md.
//
// Apple platforms only. It links SQLite3 directly, which SwiftPM does not vend on Linux, and
// `fullfsync` — the pragma this whole probe exists to measure — is Apple-specific anyway. A Linux
// number would not be a weaker version of the answer; it would be an answer to a different question.
//
// iOS is the run that counts: `fsync` on Apple platforms does not flush the drive's write cache, so
// a macOS figure is reassuring and wrong.
//
// watchOS is here for OD-020. Whether THRØ can score from the wrist turns on one measurement nobody
// has taken: a watch has a different chip, a different flash controller and a much tighter power
// budget, so `synchronous=FULL` with `fullfsync` may cost more than the 20 ms budget there. That is
// measurable rather than arguable, and the probe could not be pointed at a watch at all until this
// line. It is the platform declaration only — the run still needs a watch.
let package = Package(
    name: "DurabilityProbe",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9)],
    products: [
        .library(name: "DurabilityProbe", targets: ["DurabilityProbe"]),
        // Adjudicates a journal pulled off a device, so the kill and power-cut scripts run the one
        // pass rule in KillProbe.verdict instead of each carrying a copy in shell.
        .executable(name: "adjudicate", targets: ["adjudicate"]),
    ],
    targets: [
        .target(name: "DurabilityProbe", path: "Sources/DurabilityProbe"),
        .executableTarget(
            name: "adjudicate",
            dependencies: ["DurabilityProbe"],
            path: "Sources/adjudicate"
        ),
        .testTarget(
            name: "DurabilityProbeTests",
            dependencies: ["DurabilityProbe"],
            path: "Tests/DurabilityProbeTests"
        ),
    ]
)
