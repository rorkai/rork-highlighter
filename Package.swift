// swift-tools-version: 6.0

import PackageDescription

/// Defines the internal Clang target containing the bundled parser sources.
private let parserTarget: Target = .target(
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
