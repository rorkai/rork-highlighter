// swift-tools-version: 6.0

import PackageDescription

/// Defines the private package that renders the documentation preview.
let package = Package(
    name: "RorkHighlighterPreview",
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
            name: "PreviewGenerator",
            dependencies: [
                .product(
                    name: "RorkHighlighter",
                    package: "rork-highlighter"
                )
            ],
            resources: [
                .copy("Resources")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
