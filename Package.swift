// swift-tools-version: 6.0

import Foundation
import PackageDescription

/// Creates the source parser target used by fallback builds and artifact tools.
///
/// - Returns: A target containing the locked parser sources.
private func makeSourceParserTarget() -> Target {
    .target(
        name: "CRorkHighlighterSourceParsers",
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
    /// Loads the immutable parser artifact used by primary Apple platforms.
    private let precompiledParserTarget: Target = .binaryTarget(
        name: "CRorkHighlighterParsers",
        url:
            "https://github.com/rorkai/rork-highlighter/releases/download/parser-pack-0.3.0-r2/CRorkHighlighterParsers.xcframework.zip",
        checksum: "36ea5a3fe62453f06d0484dd50aa4281518488a9270a8b3c36d71152e694eaeb"
    )

    /// Declares source and binary parser targets needed by Apple destinations.
    private let parserTargets: [Target] =
        if buildsParsersFromSource {
            [makeSourceParserTarget()]
        } else {
            [makeSourceParserTarget(), precompiledParserTarget]
        }

    /// Selects precompiled parsers where the primary artifact has a slice.
    private let parserDependencies: [Target.Dependency] =
        if buildsParsersFromSource {
            ["CRorkHighlighterSourceParsers"]
        } else {
            [
                .target(
                    name: "CRorkHighlighterParsers",
                    condition: .when(platforms: [.macOS, .macCatalyst, .iOS])
                ),
                .target(
                    name: "CRorkHighlighterSourceParsers",
                    condition: .when(
                        platforms: [
                            .tvOS,
                            .watchOS,
                            .visionOS,
                            .linux,
                            .windows,
                            .android,
                            .wasi,
                            .openbsd,
                        ]
                    )
                ),
            ]
        }
#else
    /// Declares the source parser target on hosts without binary support.
    private let parserTargets: [Target] = [makeSourceParserTarget()]

    /// Compiles parsers from source on hosts without binary support.
    private let parserDependencies: [Target.Dependency] = [
        "CRorkHighlighterSourceParsers"
    ]
#endif

/// Defines the public highlighting library and its package dependencies.
private let rorkHighlighterTarget: Target = .target(
    name: "RorkHighlighter",
    dependencies: parserDependencies + [
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
    targets: parserTargets + [
        rorkHighlighterTarget,
        rorkHighlighterTestsTarget,
    ],
    swiftLanguageModes: [.v6],
    cLanguageStandard: .c11
)
