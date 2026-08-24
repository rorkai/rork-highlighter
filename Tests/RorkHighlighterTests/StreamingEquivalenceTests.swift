import Foundation
import Testing

@testable import RorkHighlighter

/// Verifies that incremental sessions render like one-shot highlighting.
@Suite("Streaming equivalence")
struct StreamingEquivalenceTests {
    /// Holds the Swift fixture streamed by the example application.
    private static let swiftSource = """
        import RorkCodeBlock
        import SwiftUI

        struct StreamingReply: View {
            let chunks: AsyncStream<String>
            @State private var source = ""

            var body: some View {
                CodeBlock(source, language: .swift)
                    .task {
                        for await chunk in chunks {
                            source += chunk
                        }
                    }
            }
        }
        """

    /// Holds a TypeScript fixture with generics, strings, and JSX-like tags.
    private static let typescriptSource = """
        type CodeCardProps = {
          source: string
          language: "tsx" | "typescript"
        }

        export function CodeCard({ source, language }: CodeCardProps) {
          return (
            <article aria-label={`${language} source`}>
              <pre><code>{source}</code></pre>
            </article>
          )
        }
        """

    /// Holds the fixtures replayed by the equivalence tests.
    private static let equivalenceFixtures: [(String, LanguageID)] = [
        (swiftSource, .swift),
        (typescriptSource, .typescript),
    ]

    /// Verifies that every appended revision matches one-shot captures.
    ///
    /// The session queries the complete document after each edit, so the
    /// captures must equal what a fresh highlight of the same text
    /// produces. Bounding the query to changed ranges violated this,
    /// because query patterns can match or stop matching nodes whose own
    /// structure never changed.
    @Test("Matches one-shot captures", arguments: equivalenceFixtures)
    func matchesOneShotCapturesAtEveryRevision(
        source: String,
        language: LanguageID
    ) async throws {
        let highlighter = try Highlighter()
        let session = try highlighter.makeSession("", as: language)
        let units = Array(source.utf16)
        var appended = 0

        while appended < units.count {
            let upper = min(appended + 7, units.count)
            let chunk = String(
                decoding: units[appended..<upper],
                as: UTF16.self
            )
            let update = try await session.replaceCharacters(
                in: UTF16Range(location: appended, length: 0),
                with: chunk
            )
            appended = upper

            let prefix = String(decoding: units[0..<upper], as: UTF16.self)
            let oneShot = try highlighter.highlight(prefix, as: language)
            #expect(
                update.snapshot.highlights == oneShot.highlights,
                "Captures diverged at length \(upper)"
            )
        }
    }

    /// Verifies that invalidated ranges cover every capture change.
    ///
    /// Renderers repaint only invalidated regions, so a capture that
    /// appears, disappears, or changes scope outside those regions would
    /// leave stale styles visible. The test replays the fixture and checks
    /// each capture difference between consecutive revisions against the
    /// reported rendering ranges.
    @Test("Covers every capture change with invalidation")
    func coversEveryCaptureChangeWithInvalidation() async throws {
        let highlighter = try Highlighter()
        let session = try highlighter.makeSession("", as: LanguageID.swift)
        let units = Array(Self.swiftSource.utf16)
        var appended = 0
        var previousHighlights: [HighlightSpan] = []

        while appended < units.count {
            let upper = min(appended + 7, units.count)
            let chunk = String(
                decoding: units[appended..<upper],
                as: UTF16.self
            )
            let update = try await session.replaceCharacters(
                in: UTF16Range(location: appended, length: 0),
                with: chunk
            )
            appended = upper

            let renderingRanges = update.renderingRanges
            let currentHighlights = update.snapshot.highlights
            let previousSet = Set(previousHighlights)
            let currentSet = Set(currentHighlights)
            let changedSpans =
                previousSet
                .symmetricDifference(currentSet)
                .filter { $0.range.length > 0 }

            for span in changedSpans {
                let isCovered = renderingRanges.contains { range in
                    range.location <= span.range.location
                        && span.range.upperBound <= range.upperBound
                }
                #expect(
                    isCovered,
                    "Span \(span.scope) \(span.range) escaped at \(upper)"
                )
            }
            previousHighlights = currentHighlights
        }
    }

    /// Verifies that a replacement in the middle of the source reconverges.
    @Test("Matches one-shot captures after a non-append replacement")
    func matchesOneShotCapturesAfterReplacement() async throws {
        let highlighter = try Highlighter()
        let original = "let value = 42\nlet next = 1\n"
        let session = try highlighter.makeSession(
            original,
            as: LanguageID.swift
        )

        let update = try await session.replaceCharacters(
            in: UTF16Range(location: 4, length: 5),
            with: "renamedValue"
        )
        let replaced = "let renamedValue = 42\nlet next = 1\n"
        let oneShot = try highlighter.highlight(
            replaced,
            as: LanguageID.swift
        )

        #expect(update.snapshot.text == replaced)
        #expect(update.snapshot.highlights == oneShot.highlights)
    }
}
