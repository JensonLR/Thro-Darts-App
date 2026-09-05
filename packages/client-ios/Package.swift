// swift-tools-version:5.9
import PackageDescription

// The iOS client, as Swift packages the Xcode app shell mounts. All real code lives here, under
// tests, so the app project itself stays a few lines the runbook can write out in full.
//
// The dependency graph is the point, not a detail. LATENCY_BUDGETS.md: "the scoring module must have
// no compile-time dependency on the network layer, checked in CI via the module dependency graph."
// There is no network target in this package for anything to depend on. ThroJournal reaches only
// the engine and SQLite; ThroPlay reaches the journal, the engine, the statistics and the design
// system. A future sync module depends on the journal — never the other way round.
//
// Apple platforms only, because SwiftUI and the asset catalogue are. The engine and the statistics
// are separate packages precisely so that the parts which CAN build on Linux are verified there on
// every push, rather than only when someone has a Mac.
let package = Package(
    name: "ThroClient",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ThroDesign", targets: ["ThroDesign"]),
    ],
    dependencies: [
        .package(path: "../design-tokens"),
    ],
    targets: [
        // The approved design system as SwiftUI: typography, icons, and the components the Play and
        // Home screens compose. Depends on the generated tokens and nothing else.
        .target(
            name: "ThroDesign",
            dependencies: [.product(name: "ThroTokens", package: "design-tokens")],
            path: "Sources/ThroDesign"
        ),
        .testTarget(name: "ThroDesignTests", dependencies: ["ThroDesign"], path: "Tests/ThroDesignTests"),
    ]
)
