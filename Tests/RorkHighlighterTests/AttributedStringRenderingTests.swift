#if canImport(SwiftUI)
    import Foundation
    import SwiftUI
    import Testing

    @testable import RorkHighlighter

    /// Verifies native attributed rendering and UTF-16 range safety.
    @Suite
    struct AttributedStringRenderingTests {
        /// Confirms a parsed capture receives its bundled theme color.
        @Test
        func rendersParsedCaptureWithBundledTheme() throws {
            let source = #"{"name":"Rork"}"#
            let highlighter = try Highlighter()
            let snapshot = try highlighter.highlight(source, as: .json)
            let theme = HighlightTheme.rorkDark
            let rendered = try snapshot.attributedString(theme: theme)
            let keyHighlight = snapshot.highlights.first {
                $0.scope == "string.special.key"
            }

            guard
                let keyHighlight,
                let foregroundColor = theme.style(for: keyHighlight)
                    .foregroundColor,
                let keyRange = attributedRange(
                    keyHighlight.range,
                    in: rendered
                )
            else {
                Issue.record("Expected a renderable JSON key capture.")
                return
            }

            #expect(String(rendered.characters) == source)
            #expect(
                rendered[keyRange].foregroundColor
                    == swiftUIColor(foregroundColor)
            )
        }

        /// Confirms the base style and caller font cover the complete source.
        @Test
        func appliesBaseStyleToCompleteSource() throws(HighlightRenderingError) {
            let foregroundColor = HighlightColor(
                red: 0x10,
                green: 0x20,
                blue: 0x30,
                alpha: 0x40
            )
            let backgroundColor = HighlightColor(rgb: 0xF0_E0_D0)
            let baseFont = Font.system(size: 15, design: .monospaced)
            let theme = HighlightTheme(
                name: "Complete base",
                baseStyle: HighlightStyle(
                    foregroundColor: foregroundColor,
                    backgroundColor: backgroundColor,
                    textTraits: [
                        .bold,
                        .italic,
                        .underline,
                        .strikethrough,
                    ]
                )
            )
            let snapshot = makeSnapshot(text: "let value = 1")

            let rendered = try snapshot.attributedString(
                theme: theme,
                font: baseFont
            )

            #expect(rendered.foregroundColor == swiftUIColor(foregroundColor))
            #expect(rendered.backgroundColor == swiftUIColor(backgroundColor))
            #expect(rendered.font == baseFont.bold().italic())
            #expect(
                rendered.underlineStyle == Text.LineStyle(pattern: .solid)
            )
            #expect(
                rendered.strikethroughStyle
                    == Text.LineStyle(pattern: .solid)
            )
        }

        /// Confirms later overlapping spans replace colors and remove typography.
        @Test
        func appliesOverlappingSpansInStoredOrder() throws(HighlightRenderingError) {
            let broadColor = HighlightColor(rgb: 0xAA_00_00)
            let specificColor = HighlightColor(rgb: 0x00_00_BB)
            let baseFont = Font.system(size: 13, design: .monospaced)
            let theme = HighlightTheme(
                name: "Overlap",
                styles: [
                    "broad": HighlightStyle(
                        foregroundColor: broadColor,
                        textTraits: [.underline]
                    ),
                    "specific": HighlightStyle(
                        foregroundColor: specificColor,
                        textTraits: []
                    ),
                ]
            )
            let broadRange = UTF16Range(location: 0, length: 3)
            let specificRange = UTF16Range(location: 1, length: 1)
            let snapshot = makeSnapshot(
                text: "abc",
                highlights: [
                    HighlightSpan(scope: "broad", range: broadRange),
                    HighlightSpan(scope: "specific", range: specificRange),
                ]
            )

            let rendered = try snapshot.attributedString(
                theme: theme,
                font: baseFont
            )
            guard
                let broadAttributedRange = attributedRange(
                    UTF16Range(location: 0, length: 1),
                    in: rendered
                ),
                let specificAttributedRange = attributedRange(
                    specificRange,
                    in: rendered
                )
            else {
                Issue.record("Expected valid ASCII attributed ranges.")
                return
            }

            #expect(
                rendered[broadAttributedRange].foregroundColor
                    == swiftUIColor(broadColor)
            )
            #expect(
                rendered[broadAttributedRange].underlineStyle
                    == Text.LineStyle(pattern: .solid)
            )
            #expect(
                rendered[specificAttributedRange].foregroundColor
                    == swiftUIColor(specificColor)
            )
            #expect(rendered[specificAttributedRange].font == baseFont)
            #expect(rendered[specificAttributedRange].underlineStyle == nil)
        }

        /// Confirms UTF-16 offsets after non-BMP text reach the intended capture.
        @Test
        func rendersRangeAfterEmoji() throws(HighlightRenderingError) {
            let source = "😀let"
            let baseColor = HighlightColor(rgb: 0x11_22_33)
            let keywordColor = HighlightColor(rgb: 0xAA_BB_CC)
            let keywordRange = UTF16Range(location: 2, length: 3)
            let theme = HighlightTheme(
                name: "Unicode",
                baseStyle: HighlightStyle(
                    foregroundColor: baseColor,
                    textTraits: []
                ),
                styles: [
                    "keyword": HighlightStyle(
                        foregroundColor: keywordColor
                    )
                ]
            )
            let snapshot = makeSnapshot(
                text: source,
                highlights: [
                    HighlightSpan(scope: "keyword", range: keywordRange)
                ]
            )

            let rendered = try snapshot.attributedString(theme: theme)
            guard
                let emojiRange = attributedRange(
                    UTF16Range(location: 0, length: 2),
                    in: rendered
                ),
                let keywordAttributedRange = attributedRange(
                    keywordRange,
                    in: rendered
                )
            else {
                Issue.record("Expected valid Unicode attributed ranges.")
                return
            }

            #expect(
                rendered[emojiRange].foregroundColor
                    == swiftUIColor(baseColor)
            )
            #expect(
                rendered[keywordAttributedRange].foregroundColor
                    == swiftUIColor(keywordColor)
            )
        }

        /// Confirms an out-of-bounds capture reports a typed rendering error.
        @Test
        func rejectsOutOfBoundsRange() {
            let invalidRange = UTF16Range(location: 2, length: 2)
            let snapshot = makeSnapshot(
                text: "abc",
                highlights: [
                    HighlightSpan(scope: "keyword", range: invalidRange)
                ]
            )

            #expect(
                throws:
                    HighlightRenderingError.rangeOutOfBounds(
                        range: invalidRange,
                        textLength: 3
                    )
            ) {
                try snapshot.attributedString(theme: .rorkDark)
            }
        }

        /// Confirms a capture that splits a surrogate pair is rejected.
        @Test
        func rejectsSplitUnicodeScalar() {
            let invalidRange = UTF16Range(location: 1, length: 1)
            let snapshot = makeSnapshot(
                text: "😀",
                highlights: [
                    HighlightSpan(scope: "string", range: invalidRange)
                ]
            )

            #expect(
                throws:
                    HighlightRenderingError.invalidUTF16Boundary(
                        invalidRange
                    )
            ) {
                try snapshot.attributedString(theme: .rorkDark)
            }
        }

        /// Confirms a capture that splits a composed character is rejected.
        @Test
        func rejectsSplitComposedCharacter() {
            let invalidRange = UTF16Range(location: 0, length: 1)
            let snapshot = makeSnapshot(
                text: "e\u{301}",
                highlights: [
                    HighlightSpan(scope: "string", range: invalidRange)
                ]
            )

            #expect(
                throws:
                    HighlightRenderingError.invalidUTF16Boundary(
                        invalidRange
                    )
            ) {
                try snapshot.attributedString(theme: .rorkDark)
            }
        }

        /// Confirms the public method exposes only rendering domain failures.
        @Test
        func exposesTypedRenderingContract() throws(HighlightRenderingError) {
            let snapshot = makeSnapshot(text: "let value = 1")
            let render: (HighlightTheme, Font) throws(HighlightRenderingError) -> AttributedString =
                snapshot.attributedString(theme:font:)

            _ = try render(
                .rorkLight,
                .system(.body, design: .monospaced)
            )
        }

        /// Creates a deterministic snapshot for rendering behavior tests.
        ///
        /// - Parameters:
        ///   - text: The source represented by the snapshot.
        ///   - highlights: The ordered captures applied during rendering.
        /// - Returns: A snapshot with a fixed language and revision.
        private func makeSnapshot(
            text: String,
            highlights: [HighlightSpan] = []
        ) -> HighlightSnapshot {
            HighlightSnapshot(
                text: text,
                language: .swift,
                revision: 0,
                highlights: highlights
            )
        }

        /// Converts a valid UTF-16 range into indices owned by an attributed value.
        ///
        /// - Parameters:
        ///   - range: The UTF-16 range to convert.
        ///   - attributedString: The attributed value that owns the result.
        /// - Returns: The corresponding attributed range when both boundaries are
        ///   valid.
        private func attributedRange(
            _ range: UTF16Range,
            in attributedString: AttributedString
        ) -> Range<AttributedString.Index>? {
            let text = String(attributedString.characters)
            let utf16 = text.utf16
            guard range.upperBound <= utf16.count else {
                return nil
            }
            let lowerUTF16 = utf16.index(
                utf16.startIndex,
                offsetBy: range.location
            )
            let upperUTF16 = utf16.index(
                lowerUTF16,
                offsetBy: range.length
            )
            guard
                let lowerText = String.Index(lowerUTF16, within: text),
                let upperText = String.Index(upperUTF16, within: text),
                let lowerBound = AttributedString.Index(
                    lowerText,
                    within: attributedString
                ),
                let upperBound = AttributedString.Index(
                    upperText,
                    within: attributedString
                )
            else {
                return nil
            }
            return lowerBound..<upperBound
        }

        /// Converts a renderer-neutral color into its expected SwiftUI value.
        ///
        /// - Parameter color: The color to convert.
        /// - Returns: The equivalent sRGB SwiftUI color.
        private func swiftUIColor(_ color: HighlightColor) -> Color {
            Color(
                .sRGB,
                red: Double(color.red) / 255,
                green: Double(color.green) / 255,
                blue: Double(color.blue) / 255,
                opacity: Double(color.alpha) / 255
            )
        }
    }
#endif
