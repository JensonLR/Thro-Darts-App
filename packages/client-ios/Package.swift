// swift-tools-version:5.9
import PackageDescription

// The iOS client, as Swift packages the Xcode app shell mounts. All real code lives here, under
// tests, so the app project itself stays a few lines the runbook can write out in full.
//
// The dependency graph is the point, not a detail. LATENCY_BUDGETS.md: "the scoring module must have
// no compile-time dependency on the network layer, checked in CI via the module dependency graph."
// The network target is ThroNet, and nothing the scoring path depends on may depend on it:
// ThroJournal reaches only the engine and SQLite; ThroPlay reaches the journal, the engine, the
// statistics, the design system and the surfaces outside the app it hands a leg to; ThroNet reaches
// Foundation and nothing of ours.
// Only ThroApp reaches ThroNet. `tools/check_absence_claims.py` holds the direction.
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
    // Written as version strings rather than `.iOS(.v18)`: the `.v18` and `.v15` enum cases were
    // introduced in PackageDescription 6.0, and adopting `swift-tools-version:6.0` to reach them
    // would switch every target to the Swift 6 language mode and its strict concurrency checking —
    // a migration of its own, unplanned, and nothing to do with raising a deployment floor. The
    // string form has meant exactly the same thing since tools 5.0. CI found this in thirteen
    // seconds, which is the argument for pushing a floor change on its own.
    platforms: [.iOS("18.0"), .macOS("15.0"), .watchOS("11.0")],
    products: [
        .library(name: "ThroDesign", targets: ["ThroDesign"]),
        .library(name: "ThroLiveKit", targets: ["ThroLiveKit"]),
        .library(name: "ThroWatchKit", targets: ["ThroWatchKit"]),
        .library(name: "ThroJournal", targets: ["ThroJournal"]),
        .library(name: "ThroNet", targets: ["ThroNet"]),
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

        // What a leg looks like from outside the app: the Live Activity's state, its copy, and the
        // views the Lock Screen and the Dynamic Island draw.
        //
        // Deliberately the lightest target here — tokens and nothing else. A widget extension links
        // this, and an extension that reached the journal would be linking SQLite and a scoring
        // engine into a process whose whole job is to draw two numbers. The state it carries is
        // handed to it by the app, which is also what keeps it inside ActivityKit's 4 KB budget.
        .target(
            name: "ThroLiveKit",
            dependencies: [.product(name: "ThroTokens", package: "design-tokens")],
            path: "Sources/ThroLiveKit"
        ),
        .testTarget(name: "ThroLiveKitTests", dependencies: ["ThroLiveKit"], path: "Tests/ThroLiveKitTests"),

        // A leg on a wrist (PD-077). Draws `ThroLiveState` — the same state the Lock Screen, the widgets
        // and an external display draw — in the arrangement a nearly-square screen read at arm's length
        // wants, and carries **both ends of the link that feeds it**: the phone sends from here and the
        // watch receives here, so the payload's shape cannot be written in one module and misread in
        // another.
        //
        // Its own target rather than a view inside ThroLiveKit, which is deliberately the lightest here
        // because a widget extension links it — and an extension that pulled in WatchConnectivity and a
        // watch layout would be carrying two things it can never use.
        .target(
            name: "ThroWatchKit",
            dependencies: ["ThroLiveKit", .product(name: "ThroTokens", package: "design-tokens")],
            path: "Sources/ThroWatchKit"
        ),
        .testTarget(name: "ThroWatchKitTests",
                    dependencies: ["ThroWatchKit", "ThroLiveKit"], path: "Tests/ThroWatchKitTests"),

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
                // ThroWatchKit, not for its views but for the link: `LiveBoard` is the one place a leg
                // is handed to everything outside the app, and the wrist is one more of those.
                "ThroDesign", "ThroJournal", "ThroLiveKit", "ThroWatchKit",
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
            name: "ThroNet",
            path: "Sources/ThroNet"
        ),
        .target(
            name: "ThroApp",
            dependencies: [
                "ThroNet",
                "ThroDesign", "ThroJournal", "ThroPlay", "ThroLiveKit",
                .product(name: "ThroTokens", package: "design-tokens"),
                // Named, not reached through ThroJournal: a watched match is replayed here (PD-044).
                .product(name: "ThroEngine", package: "engine-swift"),
            ],
            path: "Sources/ThroApp"
        ),
        .testTarget(name: "ThroAppTests",
                    dependencies: ["ThroApp", "ThroJournal", "ThroPlay", "ThroDesign", "ThroNet",
                                   .product(name: "ThroEngine", package: "engine-swift"),
                                   .product(name: "ThroTokens", package: "design-tokens")],
                    path: "Tests/ThroAppTests"),
    ]
)
