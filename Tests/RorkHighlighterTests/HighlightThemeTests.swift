import Foundation
import Testing

@testable import RorkHighlighter

/// Verifies renderer-neutral theme resolution and serialization.
@Suite
struct HighlightThemeTests {
    /// Confirms a packed RGB value preserves every color channel.
    @Test
    func createsColorFromPackedRGB() {
        let color = HighlightColor(rgb: 0x12_34_56, alpha: 0x78)

        #expect(color.red == 0x12)
        #expect(color.green == 0x34)
        #expect(color.blue == 0x56)
        #expect(color.alpha == 0x78)
    }

    /// Confirms dynamic packed RGB values fail without trapping when they
    /// exceed 24 bits.
    @Test
    func rejectsInvalidDynamicRGB() {
        #expect(HighlightColor.RGB(rawValue: 0xFF_FF_FF) != nil)
        #expect(HighlightColor.RGB(rawValue: 0x1_00_00_00) == nil)
    }

    /// Confirms specific scope rules refine broader rules and the base style.
    @Test
    func resolvesHierarchicalScopeStyles() {
        let background = HighlightColor(rgb: 0x10_20_30)
        let broadForeground = HighlightColor(rgb: 0x40_50_60)
        let specificForeground = HighlightColor(rgb: 0x70_80_90)
        let theme = HighlightTheme(
            name: "Hierarchy",
            baseStyle: HighlightStyle(
                backgroundColor: background,
                textTraits: []
            ),
            styles: [
                "comment": HighlightStyle(
                    foregroundColor: broadForeground,
                    textTraits: [.italic]
                ),
                "comment.documentation": HighlightStyle(
                    foregroundColor: specificForeground
                ),
            ]
        )

        let style = theme.style(for: "comment.documentation.swift")

        #expect(style.foregroundColor == specificForeground)
        #expect(style.backgroundColor == background)
        #expect(style.textTraits == [.italic])
    }

    /// Confirms an empty trait set removes typography inherited from a broader
    /// rule.
    @Test
    func clearsInheritedTextTraits() {
        let theme = HighlightTheme(
            name: "Trait refinement",
            styles: [
                "markup": HighlightStyle(
                    textTraits: [.italic]
                ),
                "markup.raw": HighlightStyle(
                    textTraits: []
                ),
            ]
        )

        #expect(
            theme.style(for: "markup.raw.block").textTraits == []
        )
    }

    /// Confirms a span and its dotted scope resolve to the same style.
    @Test
    func resolvesHighlightSpanScopes() {
        let theme = HighlightTheme(
            name: "Span lookup",
            styles: [
                "string.special": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0xAB_CD_EF)
                )
            ]
        )
        let span = HighlightSpan(
            scope: "string.special.key",
            range: UTF16Range(location: 0, length: 4)
        )

        #expect(
            theme.style(for: span)
                == theme.style(for: "string.special.key")
        )
    }

    /// Confirms snapshot-level theme resolution preserves capture order and
    /// semantic spans.
    @Test
    func createsOrderedStyledHighlights() {
        let broadSpan = HighlightSpan(
            scope: "string",
            range: UTF16Range(location: 0, length: 6)
        )
        let specificSpan = HighlightSpan(
            scope: "string.special",
            range: UTF16Range(location: 1, length: 4)
        )
        let snapshot = HighlightSnapshot(
            text: #""Rork""#,
            language: .swift,
            revision: 3,
            highlights: [broadSpan, specificSpan]
        )
        let specificStyle = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xAB_CD_EF)
        )
        let theme = HighlightTheme(
            name: "Styled highlights",
            styles: ["string.special": specificStyle]
        )

        let highlights = snapshot.styledHighlights(using: theme)

        #expect(
            highlights == [
                StyledHighlight(
                    span: broadSpan,
                    style: theme.baseStyle
                ),
                StyledHighlight(
                    span: specificSpan,
                    style: specificStyle
                ),
            ]
        )
        #expect(highlights.map(\.range) == [broadSpan.range, specificSpan.range])
    }

    /// Confirms a bundled theme resolves scopes emitted by a real parser.
    @Test
    func stylesHighlightedJSONScopes() throws(HighlighterError) {
        let highlighter = try Highlighter()
        let snapshot = try highlighter.highlight(
            #"{"name":"Rork"}"#,
            as: .json
        )
        let key = snapshot.highlights.first {
            $0.scope == "string.special.key"
        }

        #expect(key != nil)
        if let key {
            let keyStyle = HighlightTheme.rorkDark.style(for: key)
            let stringStyle = HighlightTheme.rorkDark.style(for: "string")

            #expect(keyStyle.foregroundColor != nil)
            #expect(
                keyStyle.foregroundColor
                    != stringStyle.foregroundColor
            )
        }
    }

    /// Confirms invalid and unknown scopes retain the complete base style.
    @Test
    func usesBaseStyleForUnmatchedScopes() {
        let baseStyle = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x12_34_56),
            backgroundColor: HighlightColor(rgb: 0xFF_FF_FF),
            textTraits: [.bold]
        )
        let theme = HighlightTheme(
            name: "Fallback",
            baseStyle: baseStyle,
            styles: [
                "keyword": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x65_43_21)
                )
            ]
        )

        #expect(theme.style(for: "unknown.scope") == baseStyle)
        #expect(theme.style(for: "") == baseStyle)
        #expect(theme.style(for: "keyword.") == baseStyle)
    }

    /// Confirms themes retain their value semantics through Codable.
    @Test
    func roundTripsThemeThroughCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for theme in [HighlightTheme.rorkLight, .rorkDark] {
            let decoded = try decoder.decode(
                HighlightTheme.self,
                from: encoder.encode(theme)
            )

            #expect(decoded == theme)
        }
    }

    /// Confirms bundled themes omit base backgrounds and share scope rules.
    @Test
    func providesBundledLightAndDarkThemes() {
        let lightKeyword = HighlightTheme.rorkLight.style(
            for: "keyword.function"
        )
        let darkKeyword = HighlightTheme.rorkDark.style(
            for: "keyword.function"
        )
        let darkNumber = HighlightTheme.rorkDark.style(for: "number")

        #expect(HighlightTheme.rorkLight.baseStyle.backgroundColor == nil)
        #expect(HighlightTheme.rorkDark.baseStyle.backgroundColor == nil)
        #expect(
            lightKeyword.foregroundColor
                != HighlightTheme.rorkLight.baseStyle.foregroundColor
        )
        #expect(
            darkKeyword.foregroundColor
                != HighlightTheme.rorkDark.baseStyle.foregroundColor
        )
        #expect(lightKeyword != darkKeyword)
        #expect(
            darkNumber.foregroundColor
                == HighlightColor(rgb: 0xD0_BF_69)
        )
        #expect(
            Set(HighlightTheme.rorkLight.styles.keys)
                == Set(HighlightTheme.rorkDark.styles.keys)
        )
    }
}
