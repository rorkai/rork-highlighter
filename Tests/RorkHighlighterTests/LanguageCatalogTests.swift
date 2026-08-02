import Foundation
import Testing

@testable import RorkHighlighter

/// Verifies deterministic language identifiers and catalog discovery.
@Suite
struct LanguageCatalogTests {
    /// Confirms identifiers normalize spelling used by file metadata and
    /// injection queries.
    @Test
    func normalizesLanguageIdentifiers() {
        #expect(LanguageID("  JSON\n") == .json)
        #expect(LanguageID("JsonC").rawValue == "jsonc")
    }

    /// Confirms identifiers use a compact single-string Codable
    /// representation.
    @Test
    func encodesLanguageIdentifiersAsStrings() throws {
        let data = try JSONEncoder().encode(LanguageID("TypeScript"))
        let decoded = try JSONDecoder().decode(LanguageID.self, from: data)

        #expect(String(decoding: data, as: UTF8.self) == #""typescript""#)
        #expect(decoded == .typescript)
    }

    /// Confirms the standard catalog resolves aliases and common file
    /// extensions across the bundled pack.
    @Test
    func resolvesBundledLanguageMetadata() throws {
        let catalog = try LanguageCatalog.standard()

        #expect(catalog.languages.count == 36)
        #expect(catalog.language(for: "json")?.id == .json)
        #expect(catalog.language(for: "JSONC")?.id == .json5)
        #expect(catalog.language(for: "JS")?.id == .javascript)
        #expect(catalog.language(for: "C++")?.id == .cpp)
        #expect(catalog.language(for: "markdown_inline")?.id == .markdownInline)
        #expect(catalog.language(forFileExtension: ".GeoJSON")?.id == .json)
        #expect(catalog.language(forFileExtension: ".SWIFT")?.id == .swift)
        #expect(catalog.language(forFileExtension: ".TSX")?.id == .tsx)
        #expect(catalog.language(forFileExtension: ".YML")?.id == .yaml)
        #expect(catalog.language(for: URL(fileURLWithPath: "/tmp/example.json"))?.id == .json)
        #expect(catalog.language(forFilename: "Dockerfile")?.id == .dockerfile)
        #expect(catalog.language(forFilename: ".ENV.LOCAL")?.id == .dotenv)
        #expect(catalog.language(for: URL(fileURLWithPath: "/tmp/Podfile"))?.id == .ruby)
        #expect(catalog.language(forFilename: "tsconfig.json")?.id == .json5)
        #expect(catalog.language(forFilename: "Package.resolved")?.id == .json)
        #expect(catalog.language(forFilename: "Podfile.lock")?.id == .yaml)
        #expect(catalog.language(forFilename: "Example.swift\n")?.id == .swift)
        #expect(catalog.language(forFileExtension: ".MM")?.id == .objectiveC)
    }

    /// Confirms audited Swift metadata skips injection work only when comments
    /// and regular-expression literals are impossible.
    @Test
    func preflightsBundledSwiftInjections() throws {
        let catalog = try LanguageCatalog.standard()
        let swift = try #require(catalog.language(for: .swift))

        #expect(swift.canSkipInjections(in: "let value = 42"))
        #expect(!swift.canSkipInjections(in: "// A comment"))
        #expect(!swift.canSkipInjections(in: #"let value = /a+/"#))
    }

    /// Confirms ambiguous canonical definitions fail during catalog
    /// construction.
    @Test
    func rejectsDuplicateLanguages() throws {
        let standard = try LanguageCatalog.standard()
        let json = try #require(
            standard.language(for: .json)
        )

        #expect(throws: HighlighterError.duplicateLanguage(.json)) {
            try LanguageCatalog(languages: [json, json])
        }
    }

    /// Confirms optional C parser pointers fail without requiring consumer
    /// force unwraps.
    @Test
    func rejectsMissingParser() {
        #expect(throws: HighlighterError.missingParser("example")) {
            try HighlightLanguage(
                id: "example",
                displayName: "Example",
                treeSitterLanguage: nil,
                highlightsQuery: "(identifier) @variable"
            )
        }
    }
}
