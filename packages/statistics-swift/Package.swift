// swift-tools-version:5.9
import PackageDescription

// The statistics layer in Swift, mirroring engine-swift: dependency-free so it builds and tests on
// Linux CI, where the honesty rules — an uncomputable figure says so, an approximate one is never
// a point value — are held to the same twenty assertions as the Kotlin original on every push.
let package = Package(
    name: "ThroStatistics",
    products: [
        .library(name: "ThroStatistics", targets: ["ThroStatistics"]),
    ],
    targets: [
        .target(name: "ThroStatistics", path: "Sources/ThroStatistics"),
        .testTarget(
            name: "ThroStatisticsTests",
            dependencies: ["ThroStatistics"],
            path: "Tests/ThroStatisticsTests"
        ),
    ]
)
