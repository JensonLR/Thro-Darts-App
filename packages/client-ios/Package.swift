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
        .library(name: "ThroJournal", targets: ["ThroJournal"]),
        .library(name: "ThroPlay", targets: ["ThroPlay"]),
        .library(name: "ThroApp", targets: ["ThroApp"]),
    ],
    dependencies: [
        .package(path: "../design-tokens"),
        .package(path: "../engine-swift"),
        .package(path: "../statistics-swift"),
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

        // ADR-006's on-device journal: SQLite under the measured durability configuration, verified
        // in force on every open, append-only by trigger, replayed through the engine. Reaches the
        // engine and the system SQLite and nothing else — no design, no network.
        .target(
            name: "ThroJournal",
            dependencies: [.product(name: "ThroEngine", package: "engine-swift")],
            path: "Sources/ThroJournal"
        ),
        .testTarget(name: "ThroJournalTests", dependencies: ["ThroJournal"], path: "Tests/ThroJournalTests"),

        // The Play slice: match setup, ready, scoring and result for a match scored on this device.
        // The session (engine → journal → screen, in that order) is plain Swift and tested without
        // SwiftUI; the screens only draw it.
        .target(
            name: "ThroPlay",
            dependencies: [
                "ThroDesign", "ThroJournal",
                .product(name: "ThroTokens", package: "design-tokens"),
                .product(name: "ThroEngine", package: "engine-swift"),
                .product(name: "ThroStatistics", package: "statistics-swift"),
            ],
            path: "Sources/ThroPlay"
        ),
        .testTarget(
            name: "ThroPlayTests",
            dependencies: [
                "ThroPlay", "ThroJournal",
                .product(name: "ThroEngine", package: "engine-swift"),
                .product(name: "ThroStatistics", package: "statistics-swift"),
            ],
            path: "Tests/ThroPlayTests"
        ),

        // The app shell: Home, the tab bar, and the root view the Xcode app target mounts.
        .target(
            name: "ThroApp",
            dependencies: [
                "ThroDesign", "ThroJournal", "ThroPlay",
                .product(name: "ThroTokens", package: "design-tokens"),
            ],
            path: "Sources/ThroApp"
        ),
    ]
)
