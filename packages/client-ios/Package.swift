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
//
// **The floor is iOS 18, raised from 16 on 2026-09-07.** Apple's own June 2026 figures put 79% of
// devices on iOS 26 and 14% on 18, with everything older — iOS 16 included — sharing 7%. What 16
// cost was not a rounding error: symbol effects, scroll transitions, `visualEffect`, mesh
// gradients, zoom navigation transitions, the SwiftUI Map API, EventKit's write-only access,
// interactive widgets, Control Center controls, and the Live Activity surfaces that make a Live
// Activity worth building — the Apple Watch Smart Stack among them.
//
// It cost this app less than it would cost most, because the design system already answers much of
// what the new APIs offer: `ContentUnavailableView` would be a *regression* beside the approved
// `EmptyState`, and `.sensoryFeedback` would lose `ThroHaptics`' four named events. Those stay.
// And there was not one `#available` in this client, so the raise is a pure unlock with no
// compatibility code to unpick.
let package = Package(
    name: "ThroClient",
    platforms: [.iOS(.v18), .macOS(.v15)],
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
        .testTarget(name: "ThroDesignTests",
                    dependencies: ["ThroDesign", .product(name: "ThroTokens", package: "design-tokens")],
                    path: "Tests/ThroDesignTests"),

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
        .testTarget(name: "ThroAppTests",
                    dependencies: ["ThroApp", "ThroJournal", "ThroPlay",
                                   .product(name: "ThroEngine", package: "engine-swift"),
                                   .product(name: "ThroTokens", package: "design-tokens")],
                    path: "Tests/ThroAppTests"),
    ]
)
