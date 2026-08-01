import Foundation
import Testing

@testable import RorkHighlighter

/// Verifies incremental document edits and actor-isolated state.
@Suite
struct HighlightSessionTests {
    /// Confirms an edit increments the revision and reuses the document
    /// session to produce updated captures.
    @Test
    func reparsesIncrementalEdit() async throws {
        let highlighter = try Highlighter()
        let source = #"{"value":1}"#
        let session = try highlighter.makeSession(source, as: .json)
        let numberRange = (source as NSString).range(of: "1")

        #expect(session.language == .json)

        let update = try await session.replaceCharacters(
            in: UTF16Range(
                location: numberRange.location,
                length: numberRange.length
            ),
            with: #""two""#
        )

        #expect(update.snapshot.text == #"{"value":"two"}"#)
        #expect(update.snapshot.revision == 1)
        #expect(update.snapshot.highlights.contains { $0.scope == "string" })
        #expect(update.snapshot.highlights.contains { $0.scope == "number" } == false)
        #expect(update.replacementRange.length == 5)
        #expect(await session.currentRevision == 1)
    }

    /// Confirms multiline edits after non-BMP text use correct Tree-sitter byte
    /// points.
    @Test
    func reparsesMultilineEditAfterUnicode() async throws {
        let highlighter = try Highlighter()
        let source = """
            let emoji = "😀"; let count = 1
            let enabled = false
            """
        let replacedText = "let count = 1"
        let replacement = """
            let count = 42
            let name = "Rork"
            """
        let replacedRange = (source as NSString).range(of: replacedText)
        let session = try highlighter.makeSession(source, as: .swift)

        let update = try await session.replaceCharacters(
            in: UTF16Range(
                location: replacedRange.location,
                length: replacedRange.length
            ),
            with: replacement
        )
        let expectedText = """
            let emoji = "😀"; let count = 42
            let name = "Rork"
            let enabled = false
            """
        let expectedSnapshot = try highlighter.highlight(
            expectedText,
            as: .swift
        )

        #expect(update.snapshot.text == expectedText)
        #expect(update.snapshot.highlights == expectedSnapshot.highlights)
        #expect(!update.invalidatedRanges.isEmpty)
    }

    /// Confirms sequential insertions, replacements, and deletions remain
    /// identical to complete one-shot Swift highlighting.
    @Test
    func matchesOneShotHighlightingAcrossSequentialEdits() async throws {
        let highlighter = try Highlighter()
        let initialSource = """
            import Foundation

            // Keep this comment until the deletion edit.
            let revision = 1000
            let emoji = "😀"
            let title = "Rork"
            """
        let session = try highlighter.makeSession(
            initialSource,
            as: .swift
        )
        var source = initialSource

        source = try await replace(
            "1000",
            with: "2000",
            in: source,
            using: session,
            highlighter: highlighter,
            language: .swift
        )
        let titleRange = (source as NSString).range(of: "Rork")
        let insertionRange = UTF16Range(
            location: titleRange.location + titleRange.length,
            length: 0
        )
        let insertion = " Highlighter"
        source = (source as NSString).replacingCharacters(
            in: NSRange(
                location: insertionRange.location,
                length: insertionRange.length
            ),
            with: insertion
        )
        let insertionUpdate = try await session.replaceCharacters(
            in: insertionRange,
            with: insertion
        )
        let insertionControl = try highlighter.highlight(
            source,
            as: .swift
        )

        #expect(insertionUpdate.snapshot.highlights == insertionControl.highlights)
        source = try await replace(
            "let title = \"Rork Highlighter\"",
            with: "let title = \"Rork Highlighter\"\nlet enabled = true",
            in: source,
            using: session,
            highlighter: highlighter,
            language: .swift
        )
        source = try await replace(
            "// Keep this comment until the deletion edit.\n",
            with: "",
            in: source,
            using: session,
            highlighter: highlighter,
            language: .swift
        )
        _ = try await replace(
            "\"Rork Highlighter\"",
            with: "\"Rork\\nHighlighter\"",
            in: source,
            using: session,
            highlighter: highlighter,
            language: .swift
        )
    }

    /// Confirms changed injection layers remain identical to a complete HTML
    /// highlight after embedded JavaScript and CSS edits.
    @Test
    func matchesOneShotHighlightingAcrossInjectionEdits() async throws {
        let highlighter = try Highlighter()
        let initialSource = """
            <main>
                <script>const count = 1;</script>
                <style>main { color: red; }</style>
            </main>
            """
        let session = try highlighter.makeSession(
            initialSource,
            as: .html
        )
        var source = initialSource

        source = try await replace(
            "const count = 1;",
            with: "const count = 2; const ready = true;",
            in: source,
            using: session,
            highlighter: highlighter,
            language: .html
        )
        source = try await replace(
            "color: red;",
            with: "display: grid; color: rgb(90, 212, 230);",
            in: source,
            using: session,
            highlighter: highlighter,
            language: .html
        )
        _ = try await replace(
            "<script>const count = 2; const ready = true;</script>\n    ",
            with: "",
            in: source,
            using: session,
            highlighter: highlighter,
            language: .html
        )
    }

    /// Confirms deleting the complete document clears every cached capture.
    @Test
    func clearsHighlightsWhenDocumentBecomesEmpty() async throws {
        let highlighter = try Highlighter()
        let source = "let value = 1"
        let session = try highlighter.makeSession(source, as: .swift)

        let update = try await session.replaceCharacters(
            in: UTF16Range(location: 0, length: source.utf16.count),
            with: ""
        )
        let expected = try highlighter.highlight("", as: .swift)

        #expect(update.snapshot.text.isEmpty)
        #expect(update.snapshot.highlights.isEmpty)
        #expect(update.snapshot.highlights == expected.highlights)
    }

    /// Confirms a range that splits a surrogate pair is rejected before
    /// mutating parser state.
    @Test
    func rejectsSplitUnicodeScalar() async throws {
        let highlighter = try Highlighter()
        let source = #""😀""#
        let session = try highlighter.makeSession(source, as: .json)
        let invalidRange = UTF16Range(location: 1, length: 1)

        do {
            try await session.replaceCharacters(
                in: invalidRange,
                with: "x"
            )
            Issue.record("Expected the edit to reject a split Unicode scalar.")
        } catch {
            #expect(error == .invalidUTF16Boundary(invalidRange))
        }

        #expect(await session.currentText == source)
        #expect(await session.currentRevision == 0)
    }

    /// Confirms out-of-bounds edits preserve the previous document revision.
    @Test
    func rejectsOutOfBoundsRange() async throws {
        let highlighter = try Highlighter()
        let source = #"{"value":1}"#
        let session = try highlighter.makeSession(source, as: .json)
        let invalidRange = UTF16Range(location: 100, length: 1)

        do {
            try await session.replaceCharacters(
                in: invalidRange,
                with: "0"
            )
            Issue.record("Expected the edit to reject an out-of-bounds range.")
        } catch {
            #expect(
                error
                    == .rangeOutOfBounds(
                        range: invalidRange,
                        textLength: source.utf16.count
                    )
            )
        }

        #expect(await session.currentRevision == 0)
    }

    /// Applies one located edit and compares its cached result with a complete
    /// one-shot highlight.
    ///
    /// - Parameters:
    ///   - target: The unique source fragment to replace.
    ///   - replacement: The text inserted in place of the target.
    ///   - source: The complete source before the edit.
    ///   - session: The incremental session receiving the edit.
    ///   - highlighter: The highlighter used for the one-shot control result.
    ///   - language: The language shared by both highlighting paths.
    /// - Returns: The complete source after the edit.
    /// - Throws: ``HighlighterError`` when either highlighting path fails.
    private func replace(
        _ target: String,
        with replacement: String,
        in source: String,
        using session: HighlightSession,
        highlighter: Highlighter,
        language: LanguageID
    ) async throws -> String {
        let range = (source as NSString).range(of: target)
        #expect(range.location != NSNotFound)

        let updatedSource = (source as NSString).replacingCharacters(
            in: range,
            with: replacement
        )
        let update = try await session.replaceCharacters(
            in: UTF16Range(
                location: range.location,
                length: range.length
            ),
            with: replacement
        )
        let expected = try highlighter.highlight(
            updatedSource,
            as: language
        )

        #expect(update.snapshot.text == updatedSource)
        #expect(update.snapshot.highlights == expected.highlights)
        #expect(try await session.snapshot() == update.snapshot)
        return updatedSource
    }
}
