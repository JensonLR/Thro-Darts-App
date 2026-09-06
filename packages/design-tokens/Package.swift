// swift-tools-version:5.9
import PackageDescription

// The generated token layer, as a Swift module.
//
// The target's source directory IS the generator's output directory. Nothing is copied, so
// `build.py --check` continues to govern every file here and there is no second copy to drift —
// which is ADR-010's whole rule: no platform token file is ever hand-edited. The non-Swift
// artefacts the generator writes alongside (Kotlin, CSS, the canonical JSON) are excluded rather
// than moved, because moving them would mean editing the generator's output layout to suit one
// consumer.
//
// `Color(_, bundle: .module)` in the generated Swift resolves against the processed asset
// catalogue, so light and dark are decided by the trait collection at the call site's ancestors,
// not by the call site. That is what lets a scoring screen force ink while Home stays chalk.
let package = Package(
    name: "ThroTokens",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ThroTokens", targets: ["ThroTokens"]),
    ],
    targets: [
        .target(
            name: "ThroTokens",
            path: "generated",
            exclude: ["ThroTokens.kt", "tokens.css", "tokens.json"],
            resources: [.process("Colors.xcassets")]
        ),
    ]
)
