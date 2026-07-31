import Foundation
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
}
