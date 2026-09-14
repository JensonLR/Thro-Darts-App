// swift-tools-version:5.9
import PackageDescription

// The second platform in ADR-002's spike. Deliberately dependency-free: the engine must compile
// anywhere Swift does, including Linux CI, because a scoring core that can only be built on a Mac
// cannot be verified on every push.
let package = Package(
    name: "ThroEngine",
    products: [
        .library(name: "ThroEngine", targets: ["ThroEngine"]),
    ],
    targets: [
        .target(name: "ThroEngine", path: "Sources/ThroEngine"),
        .testTarget(
            name: "ThroEngineTests",
            dependencies: ["ThroEngine"],
            path: "Tests/ThroEngineTests"
        ),
    ]
)
