import Foundation
import SwiftTreeSitter
import Testing

@testable import RorkHighlighter

/// Verifies one-shot Tree-sitter highlighting through the public API.
@Suite
struct HighlighterTests {
    /// Confirms bundled JSON produces stable Tree-sitter capture scopes.
    @Test
    func highlightsJSON() throws {
        let highlighter = try Highlighter()
        let source = #"{"name":"Rork","count":2,"enabled":true}"#

        let snapshot = try highlighter.highlight(source, as: .json)
        let scopes = Set(snapshot.highlights.map(\.scope))

        #expect(snapshot.text == source)
        #expect(snapshot.language == .json)
        #expect(snapshot.revision == 0)
        #expect(scopes.contains("string.special.key"))
        #expect(scopes.contains("string"))
        #expect(scopes.contains("number"))
        #expect(scopes.contains("constant.builtin"))
        #expect(snapshot.highlights == snapshot.highlights.sorted())
    }

    /// Confirms the optimized root query matches the general layered cursor.
    @Test
    func matchesLayeredCursorForDocumentsWithoutInjections() throws {
        let highlighter = try Highlighter()
        let source = """
            struct WelcomeView {
                let title = "Hello"
                let count = 42

                func render() {
                    _ = Screen.title
                    _ = screen.title
                }
            }
            """
        let language = try highlighter.languageDefinition(for: .swift)
        let layer = try highlighter.makeLanguageLayer(for: language)
        layer.replaceContent(with: source)
        let range = NSRange(location: 0, length: source.utf16.count)
        let matches = try layer.executeQuery(
            .highlights,
            in: range
        ).resolve(with: Predicate.Context(string: source))
        var layeredHighlights: [HighlightSpan] = []

        for match in matches {
            for capture in match.captures
            where !capture.nameComponents.isEmpty {
                layeredHighlights.append(
                    HighlightSpan(
                        scopeComponents: capture.nameComponents,
                        range: UTF16Range(
                            location: capture.range.location,
                            length: capture.range.length
                        )
                    )
                )
            }
        }
        layeredHighlights.sort()

        let optimized = try highlighter.highlight(source, as: .swift)
        let sourceText = source as NSString
        let acceptedTypeRange = sourceText.range(of: "Screen")
        let rejectedTypeRange = sourceText.range(of: "screen")

        #expect(optimized.highlights == layeredHighlights)
        #expect(
            optimized.highlights.contains {
                $0.scope == "type"
                    && $0.range
                        == UTF16Range(
                            location: acceptedTypeRange.location,
                            length: acceptedTypeRange.length
                        )
            }
        )
        #expect(
            !optimized.highlights.contains {
                $0.scope == "type"
                    && $0.range
                        == UTF16Range(
                            location: rejectedTypeRange.location,
                            length: rejectedTypeRange.length
                        )
            }
        )
    }

    /// Confirms Swift regular-expression literals retain nested regex scopes.
    @Test
    func highlightsRegexInjectedIntoSwift() throws {
        let highlighter = try Highlighter()
        let source = #"let matcher = /a+/"#
        let operatorRange = (source as NSString).range(of: "+")

        let snapshot = try highlighter.highlight(source, as: .swift)

        #expect(
            snapshot.highlights.contains {
                $0.scope == "operator"
                    && $0.range
                        == UTF16Range(
                            location: operatorRange.location,
                            length: operatorRange.length
                        )
            }
        )
    }

    /// Confirms public custom languages cannot inherit bundled preflight data
    /// by reusing a canonical identifier.
    @Test
    func evaluatesCustomSwiftInjectionQueries() throws {
        let standardCatalog = try LanguageCatalog.standard()
        let bundledSwift = try #require(
            standardCatalog.language(for: .swift)
        )
        let regex = try #require(
            standardCatalog.language(for: .regex)
        )
        let customSwift = try HighlightLanguage(
            id: .swift,
            displayName: "Custom Swift",
            treeSitterLanguage:
                bundledSwift.configuration.language.tsLanguage,
            highlightsQuery: "(simple_identifier) @variable",
            injectionsQuery: """
                ((simple_identifier) @injection.content
                 (#set! injection.language "regex"))
                """
        )
        let catalog = try LanguageCatalog(
            languages: [customSwift, regex]
        )
        let highlighter = Highlighter(catalog: catalog)

        let snapshot = try highlighter.highlight("abc", as: .swift)

        #expect(customSwift.injectionTriggerByte == nil)
        #expect(snapshot.highlights.contains { $0.scope == "string" })
    }

    /// Confirms public ranges use Foundation-compatible UTF-16 offsets.
    @Test
    func reportsUnicodeRangesInUTF16() throws {
        let highlighter = try Highlighter()
        let source = #"{"emoji":"😀"}"#
        let expectedRange = (source as NSString).range(of: #""😀""#)

        let snapshot = try highlighter.highlight(source, as: .json)
        let emojiString = snapshot.highlights.first {
            $0.scope == "string"
                && $0.range
                    == UTF16Range(
                        location: expectedRange.location,
                        length: expectedRange.length
                    )
        }

        #expect(emojiString != nil)
    }

    /// Confirms file-based discovery selects the matching bundled language.
    @Test
    func highlightsUsingFileURL() throws {
        let highlighter = try Highlighter()
        let fileURL = URL(fileURLWithPath: "/tmp/settings.JSON")

        let snapshot = try highlighter.highlight(
            #"{"enabled":true}"#,
            for: fileURL
        )

        #expect(snapshot.language == .json)
    }

    /// Confirms typed UTF-16 ranges mirror standard range overlap semantics.
    @Test
    func comparesUTF16RangeOverlap() {
        let range = UTF16Range(location: 2, length: 4)

        #expect(range.overlaps(UTF16Range(location: 5, length: 2)))
        #expect(!range.overlaps(UTF16Range(location: 6, length: 2)))
        #expect(!range.overlaps(UTF16Range(location: 4, length: 0)))
    }

    /// Confirms spans with equal ranges sort by scope specificity and then
    /// lexical scope order.
    @Test
    func ordersEqualRangeHighlightSpansDeterministically() {
        let range = UTF16Range(location: 2, length: 4)
        let spans = [
            HighlightSpan(
                scopeComponents: ["variable", "property"],
                range: range
            ),
            HighlightSpan(scope: "variable", range: range),
            HighlightSpan(
                scopeComponents: ["variable", "parameter"],
                range: range
            ),
        ]

        #expect(
            spans.sorted().map(\.scope)
                == [
                    "variable",
                    "variable.parameter",
                    "variable.property",
                ]
        )
    }

    /// Confirms internal range provenance does not change public snapshot
    /// equality or hashing.
    @Test
    func ignoresRangeProvenanceInSnapshotValueSemantics() throws {
        let highlighter = try Highlighter()
        let parsed = try highlighter.highlight(
            "let value = 1",
            as: .swift
        )
        let reconstructed = HighlightSnapshot(
            text: parsed.text,
            language: parsed.language,
            revision: parsed.revision,
            highlights: parsed.highlights
        )

        #expect(parsed == reconstructed)
        #expect(Set([parsed, reconstructed]).count == 1)
    }

    /// Confirms Codable round trips preserve validated public value types.
    @Test
    func roundTripsValidatedCodableValues() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let range = UTF16Range(location: 12, length: 4)
        let configuration = HighlighterConfiguration(
            maximumInjectionDepth: 8
        )

        let decodedRange = try decoder.decode(
            UTF16Range.self,
            from: encoder.encode(range)
        )
        let decodedConfiguration = try decoder.decode(
            HighlighterConfiguration.self,
            from: encoder.encode(configuration)
        )

        #expect(decodedRange == range)
        #expect(decodedConfiguration == configuration)
    }

    /// Confirms decoding cannot create ranges that violate initializer
    /// invariants.
    @Test
    func rejectsInvalidDecodedUTF16Ranges() {
        let payloads = [
            #"{"location":-1,"length":1}"#,
            #"{"location":1,"length":-1}"#,
            #"{"location":\#(Int.max),"length":1}"#,
        ]

        for payload in payloads {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(
                    UTF16Range.self,
                    from: Data(payload.utf8)
                )
            }
        }
    }

    /// Confirms decoding cannot create a negative language injection depth.
    @Test
    func rejectsInvalidDecodedHighlighterConfiguration() {
        let payload = #"{"maximumInjectionDepth":-1}"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                HighlighterConfiguration.self,
                from: Data(payload.utf8)
            )
        }
    }
}
