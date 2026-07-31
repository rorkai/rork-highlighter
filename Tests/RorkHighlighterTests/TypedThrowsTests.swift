import Foundation
import Testing

@testable import RorkHighlighter

/// Verifies typed error contracts across the public highlighting API.
@Suite
struct TypedThrowsTests {
    /// Confirms one-shot, catalog, and session operations expose only domain
    /// errors.
    @Test
    func exposesHighlighterErrorContracts() async throws(HighlighterError) {
        let makeCatalog: () throws(HighlighterError) -> LanguageCatalog = {
            try .standard()
        }
        let makeHighlighter: () throws(HighlighterError) -> Highlighter = {
            try Highlighter()
        }
        let makeMissingParserLanguage: () throws(HighlighterError) -> HighlightLanguage =
            {
                try HighlightLanguage(
                    id: "missing",
                    displayName: "Missing",
                    treeSitterLanguage: nil,
                    highlightsQuery: "(identifier) @variable"
                )
            }

        let catalog = try makeCatalog()
        let rebuildCatalog: ([HighlightLanguage]) throws(HighlighterError) -> LanguageCatalog =
            {
                try LanguageCatalog(languages: $0)
            }
        _ = try rebuildCatalog(catalog.languages)

        let highlighter = try makeHighlighter()
        let highlightByIdentifier:
            (String, LanguageID) throws(HighlighterError) -> HighlightSnapshot =
                highlighter.highlight(_:as:)
        let highlightByURL: (String, URL) throws(HighlighterError) -> HighlightSnapshot =
            highlighter.highlight(_:for:)
        let makeSession: (String, LanguageID) throws(HighlighterError) -> HighlightSession =
            highlighter.makeSession(_:as:)

        _ = try highlightByIdentifier("let value = 1", .swift)
        _ = try highlightByURL(
            #"{"value":1}"#,
            URL(fileURLWithPath: "/tmp/value.json")
        )

        let session = try makeSession(#"{"value":1}"#, .json)
        let snapshot: () async throws(HighlighterError) -> HighlightSnapshot =
            {
                try await session.snapshot()
            }
        let replaceCharacters:
            (UTF16Range, String) async throws(HighlighterError) -> HighlightUpdate =
                { range, replacement in
                    try await session.replaceCharacters(
                        in: range,
                        with: replacement
                    )
                }

        _ = try await snapshot()
        _ = try await replaceCharacters(
            UTF16Range(location: 9, length: 1),
            "2"
        )
        #expect(throws: HighlighterError.missingParser("missing")) {
            try makeMissingParserLanguage()
        }
    }
}
