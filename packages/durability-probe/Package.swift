// swift-tools-version:5.9
import PackageDescription

// ADR-006 requires the durability latency of a visit write to be MEASURED on both reference
// devices before the client architecture is fixed. This package is that measurement and nothing
// else — it writes synthetic visits under each candidate SQLite configuration and reports the
// distribution against the budget in LATENCY_BUDGETS.md.
//
// iOS is declared because the answer differs there: `fsync` on Apple platforms does not flush the
// drive's write cache, so a macOS number would be reassuring and wrong.
let package = Package(
    name: "DurabilityProbe",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "DurabilityProbe", targets: ["DurabilityProbe"]),
    ],
    targets: [
        .target(name: "DurabilityProbe", path: "Sources/DurabilityProbe"),
        .testTarget(
            name: "DurabilityProbeTests",
            dependencies: ["DurabilityProbe"],
            path: "Tests/DurabilityProbeTests"
        ),
    ]
)
