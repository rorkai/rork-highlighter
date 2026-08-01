// swift-tools-version: 6.1

import PackageDescription

/// Defines the opt-in package that compares Rork Highlighter with other
/// highlighting implementations.
let package = Package(
    name: "RorkHighlighterComparisonBenchmarks",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(
            name: "rork-highlighter",
            path: "../.."
        ),
        .package(
            url: "https://github.com/PhraseHQ/HighlightKit.git",
            exact: "0.2.0"
        ),
        .package(
            url: "https://github.com/atacan/swift-highlight.git",
            revision: "6571a6d3177780feb3cc3e02d70081f4882aa339"
        ),
        .package(
            url: "https://github.com/ordo-one/benchmark",
            exact: "1.36.2"
        ),
    ],
    targets: [
        .executableTarget(
            name: "HighlighterComparisonBenchmarks",
            dependencies: [
                .product(
                    name: "RorkHighlighter",
                    package: "rork-highlighter"
                ),
                .product(
                    name: "HighlightKit",
                    package: "HighlightKit"
                ),
                .product(
                    name: "SwiftHighlight",
                    package: "swift-highlight"
                ),
                .product(
                    name: "Benchmark",
                    package: "benchmark"
                ),
            ],
            path: "Benchmarks/HighlighterComparisonBenchmarks",
            plugins: [
                .plugin(
                    name: "BenchmarkPlugin",
                    package: "benchmark"
                )
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
