import Foundation
import Testing

@testable import RorkHighlighter

/// Verifies the stability boundary reported for streamed source prefixes.
@Suite("Parse stability")
struct ParseStabilityTests {
    /// Verifies that source ending at a token keeps that token speculative.
    ///
    /// Appending one character can extend a trailing token, so the token's
    /// classification is not settled until a separator follows it.
    @Test("Withholds a trailing flush token")
    func withholdsTrailingFlushToken() throws {
        let highlighter = try Highlighter()
        let snapshot = try highlighter.highlight("let value = 42", as: .swift)

        #expect(snapshot.stableUTF16Length == 12)
    }

    /// Verifies that a trailing separator settles the complete source.
    @Test("Settles source ending in whitespace")
    func settlesSourceEndingInWhitespace() throws {
        let highlighter = try Highlighter()
        let snapshot = try highlighter.highlight("let value = 42\n", as: .swift)

        #expect(snapshot.stableUTF16Length == 15)
    }

    /// Verifies that an unterminated string literal stays speculative.
    ///
    /// The parser recovers the literal by inventing a closing quote, and a
    /// later chunk can still turn the literal into something else, so no
    /// part of the literal's content may settle.
    @Test("Withholds an unterminated string")
    func withholdsUnterminatedString() throws {
        let highlighter = try Highlighter()
        let source = "let greeting = \"Hello"
        let snapshot = try highlighter.highlight(source, as: .swift)
        let stableUTF16Length = try #require(snapshot.stableUTF16Length)

        #expect(stableUTF16Length <= 16)
        #expect(stableUTF16Length >= 14)
    }

    /// Verifies that an unterminated multiline string stays speculative.
    ///
    /// The opening delimiter settles because the literal remains a string in
    /// every continuation, while the growing content cannot settle before
    /// the closing delimiter arrives.
    @Test("Withholds unterminated multiline string content")
    func withholdsUnterminatedMultilineStringContent() throws {
        let highlighter = try Highlighter()
        let source = "let s = \"\"\"\nfirst line\nsecond"
        let snapshot = try highlighter.highlight(source, as: .swift)
        let stableUTF16Length = try #require(snapshot.stableUTF16Length)

        #expect(stableUTF16Length >= 8)
        #expect(stableUTF16Length <= 12)
    }

    /// Verifies that a trailing member access keeps its chain speculative.
    ///
    /// With the member name absent, the parser classifies the chain's
    /// receiver as a type, and that classification flips once the member
    /// arrives. The whole chain has to stay speculative even though the
    /// grammar reports no parse error for it.
    @Test("Withholds a member chain with a trailing dot")
    func withholdsMemberChainWithTrailingDot() throws {
        let highlighter = try Highlighter()
        let source = "let name = person.name."
        let snapshot = try highlighter.highlight(source, as: .swift)
        let stableUTF16Length = try #require(snapshot.stableUTF16Length)

        // The navigation expression begins at offset eleven.
        #expect(stableUTF16Length <= 11)
    }

    /// Verifies that a completed member chain settles.
    @Test("Settles a completed member chain")
    func settlesCompletedMemberChain() throws {
        let highlighter = try Highlighter()
        let source = "let name = person.name.first\n"
        let snapshot = try highlighter.highlight(source, as: .swift)

        #expect(snapshot.stableUTF16Length == source.utf16.count)
    }

    /// Verifies that a call with open arguments reveals its function name.
    ///
    /// The parser recognizes the call while its argument list streams, and
    /// the name keeps the classification the finished call will have, so
    /// only the trailing flush token stays speculative.
    @Test("Settles a call name while arguments stream")
    func settlesCallNameWhileArgumentsStream() throws {
        let highlighter = try Highlighter()
        let source = "let total = compute(40,"
        let snapshot = try highlighter.highlight(source, as: .swift)
        let stableUTF16Length = try #require(snapshot.stableUTF16Length)

        // Everything before the trailing comma settles, including the
        // called function name at offsets twelve through eighteen.
        #expect(stableUTF16Length == 22)
    }

    /// Verifies that an open trailing comment stays speculative.
    ///
    /// The comment token grows with every appended chunk, so its content
    /// cannot settle before its line ends, while the code before it keeps
    /// its settled classifications.
    @Test("Withholds an open trailing comment")
    func withholdsOpenTrailingComment() throws {
        let highlighter = try Highlighter()
        let open = try highlighter.highlight("let x = 1 // no", as: .swift)
        let closed = try highlighter.highlight(
            "let x = 1 // note\n",
            as: .swift
        )

        #expect(open.stableUTF16Length == 10)
        #expect(closed.stableUTF16Length == 18)
    }

    /// Verifies that recovery reaching the end keeps its region speculative.
    ///
    /// While a construct streams inside Tree-sitter's `ERROR` recovery, the
    /// parser reinterprets the whole region on later chunks, so nothing
    /// inside the error node may settle.
    @Test("Withholds an end-connected error region")
    func withholdsEndConnectedErrorRegion() throws {
        let highlighter = try Highlighter()
        let source = """
            import SwiftUI

            struct StreamingReply: View {
                let chunks: AsyncStream<Str
            """
        let snapshot = try highlighter.highlight(source, as: .swift)
        let stableUTF16Length = try #require(snapshot.stableUTF16Length)

        // The error region begins at the struct keyword. Both imports stay
        // settled while everything from the struct onward remains open.
        #expect(stableUTF16Length == 16)
    }

    /// Verifies that trailing whitespace does not disconnect recovery.
    ///
    /// Indentation between an error region and the document end carries no
    /// tokens, so the region still owns the document tail.
    @Test("Bridges whitespace between recovery and the end")
    func bridgesWhitespaceBetweenRecoveryAndEnd() throws {
        let highlighter = try Highlighter()
        let source = "type CodeCardProps = {\n  source: string\n  "
        let snapshot = try highlighter.highlight(source, as: .typescript)

        #expect(snapshot.stableUTF16Length == 0)
    }

    /// Verifies that a missing closing token settles the parsed children.
    ///
    /// The parser inserts a zero-width `MISSING` brace while it still
    /// recognizes the surrounding declaration, so the declaration's parsed
    /// children keep their final classifications and stay revealed.
    @Test("Settles parsed children behind a missing closer")
    func settlesParsedChildrenBehindMissingCloser() throws {
        let highlighter = try Highlighter()
        let source = """
            struct Reply: View {
                let value = 42
            """
        let snapshot = try highlighter.highlight(source, as: .swift)
        let stableUTF16Length = try #require(snapshot.stableUTF16Length)

        // Everything up to the trailing flush token can settle even though
        // the struct body is still open.
        #expect(stableUTF16Length >= source.utf16.count - 2)
    }

    /// Verifies that settled malformed source does not poison the tail.
    ///
    /// An error region followed by settled tokens parses the same way a
    /// finished document would, so only the genuine tail stays speculative.
    @Test("Keeps a mid-document error region settled")
    func keepsMidDocumentErrorRegionSettled() throws {
        let highlighter = try Highlighter()
        let source = """
            let broken = @@
            let after = 1
            let final = 2
            """
        let snapshot = try highlighter.highlight(source, as: .swift)
        let stableUTF16Length = try #require(snapshot.stableUTF16Length)

        #expect(stableUTF16Length >= source.utf16.count - 2)
    }

    /// Verifies that injected languages refine the stability boundary.
    ///
    /// The Markdown block grammar sees an open fence as one growing token,
    /// but the injected language parses the fence content, so its finer
    /// tokens decide how much of the content settles.
    @Test("Refines the boundary through an injected fence")
    func refinesBoundaryThroughInjectedFence() throws {
        let highlighter = try Highlighter()
        let source = "```swift\nlet value = 42\nlet next"
        let snapshot = try highlighter.highlight(source, as: .markdown)
        let stableUTF16Length = try #require(snapshot.stableUTF16Length)

        // Only the trailing flush identifier of the injected Swift layer
        // stays speculative, not the whole fence content.
        #expect(stableUTF16Length == 28)
    }

    /// Verifies that an error-free Markdown prefix settles completely.
    @Test("Settles error-free Markdown")
    func settlesErrorFreeMarkdown() throws {
        let highlighter = try Highlighter()
        let source = "# Title\n\nSome **bold te"
        let snapshot = try highlighter.highlight(source, as: .markdown)

        #expect(snapshot.stableUTF16Length == source.utf16.count)
    }

    /// Verifies that stability boundaries respect surrogate pairs.
    @Test("Reports scalar-aligned boundaries for non-ASCII source")
    func reportsScalarAlignedBoundaries() throws {
        let highlighter = try Highlighter()
        let source = "let emoji = \"🚀🚀"
        let snapshot = try highlighter.highlight(source, as: .swift)
        let stableUTF16Length = try #require(snapshot.stableUTF16Length)
        let units = Array(source.utf16)

        #expect(stableUTF16Length <= 13)
        if stableUTF16Length < units.count {
            let unit = units[stableUTF16Length]
            #expect(!(0xDC00...0xDFFF).contains(unit))
        }
    }

    /// Verifies that an empty document reports an empty stable prefix.
    @Test("Reports zero for an empty document")
    func reportsZeroForEmptyDocument() throws {
        let highlighter = try Highlighter()
        let snapshot = try highlighter.highlight("", as: .swift)

        #expect(snapshot.stableUTF16Length == 0)
    }

    /// Verifies that whitespace-only source settles completely.
    @Test("Settles whitespace-only source")
    func settlesWhitespaceOnlySource() throws {
        let highlighter = try Highlighter()
        let snapshot = try highlighter.highlight("  \n\t\n", as: .swift)

        #expect(snapshot.stableUTF16Length == 5)
    }

    /// Verifies that sessions report the same boundary as one-shot parsing.
    @Test("Matches one-shot stability after incremental appends")
    func matchesOneShotStabilityAfterIncrementalAppends() async throws {
        let highlighter = try Highlighter()
        let source = """
            import SwiftUI

            struct Reply: View {
                let value = 42
            }
            """
        let session = try highlighter.makeSession("", as: .swift)

        var appended = 0
        let units = Array(source.utf16)
        while appended < units.count {
            let upper = min(appended + 7, units.count)
            let chunk = String(
                decoding: units[appended..<upper],
                as: UTF16.self
            )
            try await session.replaceCharacters(
                in: UTF16Range(location: appended, length: 0),
                with: chunk
            )
            appended = upper
        }

        let sessionSnapshot = try await session.snapshot()
        let oneShot = try highlighter.highlight(source, as: .swift)

        #expect(
            sessionSnapshot.stableUTF16Length == oneShot.stableUTF16Length
        )
    }

    /// Verifies that hand-built snapshots clamp the supplied boundary.
    @Test("Clamps the public boundary to the text length")
    func clampsPublicBoundaryToTextLength() {
        let oversized = HighlightSnapshot(
            text: "abc",
            language: .swift,
            revision: 0,
            highlights: [],
            stableUTF16Length: 99
        )
        let negative = HighlightSnapshot(
            text: "abc",
            language: .swift,
            revision: 0,
            highlights: [],
            stableUTF16Length: -1
        )
        let unknown = HighlightSnapshot(
            text: "abc",
            language: .swift,
            revision: 0,
            highlights: []
        )
        let midSurrogate = HighlightSnapshot(
            text: "🚀x",
            language: .swift,
            revision: 0,
            highlights: [],
            stableUTF16Length: 1
        )

        #expect(oversized.stableUTF16Length == 3)
        #expect(negative.stableUTF16Length == 0)
        #expect(unknown.stableUTF16Length == nil)
        #expect(midSurrogate.stableUTF16Length == 0)
    }
}
