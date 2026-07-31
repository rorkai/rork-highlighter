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
}
