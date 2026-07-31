// swift-tools-version: 6.0

import PackageDescription

/// Defines the private package that measures public highlighting workflows.
let package = Package(
    name: "RorkHighlighterBenchmarks",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(
            name: "rork-highlighter",
            path: ".."
        ),
        .package(
            url: "https://github.com/ordo-one/benchmark",
            exact: "1.36.2"
        ),
    ],
    targets: [
        .executableTarget(
            name: "RorkHighlighterBenchmarks",
            dependencies: [
                .product(
                    name: "Benchmark",
                    package: "benchmark"
                ),
                .product(
                    name: "RorkHighlighter",
                    package: "rork-highlighter"
                ),
            ],
            path: "Benchmarks/RorkHighlighterBenchmarks",
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
