// swift-tools-version: 6.0

import Foundation
import PackageDescription

/// Creates the source parser target used by fallback builds and artifact tools.
///
/// - Returns: A target containing the locked parser sources.
private func makeSourceParserTarget() -> Target {
    .target(
        name: "CRorkHighlighterParsers",
        path: "Sources/CRorkHighlighterParsers",
        exclude: [
            "languages/dockerfile/scanner.c",
            "languages/python/scanner.c",
            "languages/sql/scanner.c",
            "languages/yaml/scanner.c",
            "languages/yaml/schema.core.c",
        ],
        sources: ["languages", "wrappers"],
        publicHeadersPath: "include"
    )
}

/// Reports whether this build explicitly requests source parser compilation.
private let buildsParsersFromSource =
    ProcessInfo.processInfo.environment[
        "RORK_HIGHLIGHTER_BUILD_PARSERS_FROM_SOURCE"
    ] == "1"

#if os(macOS)
    /// Selects source parsers when requested and the Apple artifact otherwise.
    private let parserTarget: Target =
        if buildsParsersFromSource {
            makeSourceParserTarget()
        } else {
            .binaryTarget(
                name: "CRorkHighlighterParsers",
                url:
                    "https://github.com/rorkai/rork-highlighter/releases/download/parser-pack-0.3.0-r1/CRorkHighlighterParsers.xcframework.zip",
                checksum: "275891b594d9cdf10aced8a9b2db769c0f19696269980b8732957b6ff0f6495a"
            )
        }
#else
    /// Compiles the bundled parser sources on hosts without Apple binary support.
    private let parserTarget: Target = makeSourceParserTarget()
#endif

/// Defines the public highlighting library and its package dependencies.
private let rorkHighlighterTarget: Target = .target(
    name: "RorkHighlighter",
    dependencies: [
        "CRorkHighlighterParsers",
        .product(
            name: "SwiftTreeSitter",
            package: "swift-tree-sitter"
        ),
        .product(
            name: "SwiftTreeSitterLayer",
            package: "swift-tree-sitter"
        ),
    ],
    resources: [
        .copy("Resources/Languages")
    ]
)

/// Defines the validation target for the public highlighting library.
private let rorkHighlighterTestsTarget: Target = .testTarget(
    name: "RorkHighlighterTests",
    dependencies: [
        "RorkHighlighter",
        .product(
            name: "SwiftTreeSitter",
            package: "swift-tree-sitter"
        ),
    ]
)

/// Defines the Swift library, its bundled parser target, and its validation
/// tests.
let package = Package(
    name: "rork-highlighter",
    platforms: [
        .macOS(.v13),
        .macCatalyst(.v16),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "RorkHighlighter",
            targets: ["RorkHighlighter"]
        )
    ],
    dependencies: [
        // This preview supplies lightweight predicate-aware captures until an upstream release includes them.
        .package(
            url: "https://github.com/rorkai/swift-tree-sitter.git",
            exact: "0.25.1-rork.3"
        )
    ],
    targets: [
        parserTarget,
        rorkHighlighterTarget,
        rorkHighlighterTestsTarget,
    ],
    swiftLanguageModes: [.v6],
    cLanguageStandard: .c11
)
