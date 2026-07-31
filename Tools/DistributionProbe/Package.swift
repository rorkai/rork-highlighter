// swift-tools-version: 6.0

import PackageDescription

/// Defines the private executable used for linked-size measurements.
let package = Package(
    name: "RorkHighlighterDistributionProbe",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(
            name: "rork-highlighter",
            path: "../.."
        )
    ],
    targets: [
        .executableTarget(
            name: "DistributionProbe",
            dependencies: [
                .product(
                    name: "RorkHighlighter",
                    package: "rork-highlighter"
                )
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
