#if canImport(UIKit)
    import Testing
    import UIKit

    /// Names the UIKit font used by shared native rendering tests.
    private typealias TestNativeFont = UIFont

    /// Names the UIKit color used by shared native rendering tests.
    private typealias TestNativeColor = UIColor
#elseif canImport(AppKit)
    import AppKit
    import Testing

    /// Names the AppKit font used by shared native rendering tests.
    private typealias TestNativeFont = NSFont

    /// Names the AppKit color used by shared native rendering tests.
    private typealias TestNativeColor = NSColor
#endif

#if canImport(UIKit) || canImport(AppKit)
    @testable import RorkHighlighter

    /// Verifies TextKit rendering through native platform attributes.
    @Suite
    struct NSAttributedStringRenderingTests {
        /// Confirms a parsed capture receives its bundled theme color.
        @Test
        func rendersParsedCaptureWithNativeAttributes() throws {
            let source = #"{"name":"Rork"}"#
            let highlighter = try Highlighter()
            let snapshot = try highlighter.highlight(source, as: .json)
            let theme = HighlightTheme.rorkDark
            let rendered = try snapshot.nsAttributedString(theme: theme)
            let keyHighlight = snapshot.highlights.first {
                $0.scope == "string.special.key"
            }

            guard
                let keyHighlight,
                let foregroundColor = theme.style(for: keyHighlight)
                    .foregroundColor
            else {
                Issue.record("Expected a styled JSON key capture.")
                return
            }
            let attributes = rendered.attributes(
                at: keyHighlight.range.location,
                effectiveRange: nil
            )

            #expect(rendered.string == source)
            #expect(
                color(
                    attributes[.foregroundColor],
                    matches: foregroundColor
                )
            )
        }

        /// Confirms base colors and typography cover the complete source.
        @Test
        func appliesBaseStyleToCompleteSource() throws(HighlightRenderingError) {
            let foregroundColor = HighlightColor(
                red: 0x10,
                green: 0x20,
                blue: 0x30,
                alpha: 0x40
            )
            let backgroundColor = HighlightColor(rgb: 0xF0_E0_D0)
            let baseFont = TestNativeFont.monospacedSystemFont(
                ofSize: 15,
                weight: .regular
            )
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

            let rendered = try snapshot.nsAttributedString(
                theme: theme,
                font: baseFont
            )
            var effectiveRange = NSRange(location: 0, length: 0)
            let attributes = rendered.attributes(
                at: 0,
                effectiveRange: &effectiveRange
            )
            let renderedFont = attributes[.font] as? TestNativeFont

            #expect(
                effectiveRange
                    == NSRange(location: 0, length: rendered.length)
            )
            #expect(
                color(
                    attributes[.foregroundColor],
                    matches: foregroundColor
                )
            )
            #expect(
                color(
                    attributes[.backgroundColor],
                    matches: backgroundColor
                )
            )
            #expect(renderedFont.map(fontIsBold) == true)
            #expect(renderedFont.map(fontIsItalic) == true)
            #expect(
                attributes[.underlineStyle] as? Int
                    == NSUnderlineStyle.single.rawValue
            )
            #expect(
                attributes[.strikethroughStyle] as? Int
                    == NSUnderlineStyle.single.rawValue
            )
        }

        /// Confirms theme traits build on the caller-provided font face.
        @Test
        func preservesCallerFontTraits() throws(HighlightRenderingError) {
            let baseFont = TestNativeFont.monospacedSystemFont(
                ofSize: 15,
                weight: .bold
            )
            let theme = HighlightTheme(
                name: "Caller font",
                baseStyle: HighlightStyle(textTraits: [])
            )
            let snapshot = makeSnapshot(text: "let value = 1")

            let rendered = try snapshot.nsAttributedString(
                theme: theme,
                font: baseFont
            )
            let renderedFont =
                rendered.attribute(
                    .font,
                    at: 0,
                    effectiveRange: nil
                ) as? TestNativeFont

            #expect(renderedFont.map(fontIsBold) == true)
        }

        /// Confirms later overlapping spans replace colors and remove typography.
        @Test
        func appliesOverlappingSpansInStoredOrder() throws(HighlightRenderingError) {
            let broadColor = HighlightColor(rgb: 0xAA_00_00)
            let specificColor = HighlightColor(rgb: 0x00_00_BB)
            let baseFont = TestNativeFont.monospacedSystemFont(
                ofSize: 13,
                weight: .regular
            )
            let theme = HighlightTheme(
                name: "Overlap",
                styles: [
                    "broad": HighlightStyle(
                        foregroundColor: broadColor,
                        textTraits: [.underline, .strikethrough]
                    ),
                    "specific": HighlightStyle(
                        foregroundColor: specificColor,
                        textTraits: []
                    ),
                ]
            )
            let snapshot = makeSnapshot(
                text: "abc",
                highlights: [
                    HighlightSpan(
                        scope: "broad",
                        range: UTF16Range(location: 0, length: 3)
                    ),
                    HighlightSpan(
                        scope: "specific",
                        range: UTF16Range(location: 1, length: 1)
                    ),
                ]
            )

            let rendered = try snapshot.nsAttributedString(
                theme: theme,
                font: baseFont
            )
            let broadAttributes = rendered.attributes(
                at: 0,
                effectiveRange: nil
            )
            let specificAttributes = rendered.attributes(
                at: 1,
                effectiveRange: nil
            )

            #expect(
                color(
                    broadAttributes[.foregroundColor],
                    matches: broadColor
                )
            )
            #expect(
                broadAttributes[.underlineStyle] as? Int
                    == NSUnderlineStyle.single.rawValue
            )
            #expect(
                broadAttributes[.strikethroughStyle] as? Int
                    == NSUnderlineStyle.single.rawValue
            )
            #expect(
                color(
                    specificAttributes[.foregroundColor],
                    matches: specificColor
                )
            )
            #expect(specificAttributes[.font] as? TestNativeFont == baseFont)
            #expect(specificAttributes[.underlineStyle] == nil)
            #expect(specificAttributes[.strikethroughStyle] == nil)
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

            let rendered = try snapshot.nsAttributedString(theme: theme)
            let emojiAttributes = rendered.attributes(
                at: 0,
                effectiveRange: nil
            )
            var keywordEffectiveRange = NSRange(location: 0, length: 0)
            let keywordAttributes = rendered.attributes(
                at: keywordRange.location,
                effectiveRange: &keywordEffectiveRange
            )

            #expect(
                keywordEffectiveRange
                    == NSRange(
                        location: keywordRange.location,
                        length: keywordRange.length
                    )
            )
            #expect(
                color(
                    emojiAttributes[.foregroundColor],
                    matches: baseColor
                )
            )
            #expect(
                color(
                    keywordAttributes[.foregroundColor],
                    matches: keywordColor
                )
            )
        }

        /// Confirms invalid native ranges report typed rendering errors.
        @Test
        func rejectsInvalidRanges() {
            let outOfBoundsRange = UTF16Range(location: 2, length: 2)
            let splitCharacterRange = UTF16Range(location: 0, length: 1)
            let outOfBoundsSnapshot = makeSnapshot(
                text: "abc",
                highlights: [
                    HighlightSpan(
                        scope: "keyword",
                        range: outOfBoundsRange
                    )
                ]
            )
            let splitCharacterSnapshot = makeSnapshot(
                text: "e\u{301}",
                highlights: [
                    HighlightSpan(
                        scope: "string",
                        range: splitCharacterRange
                    )
                ]
            )

            #expect(
                throws:
                    HighlightRenderingError.rangeOutOfBounds(
                        range: outOfBoundsRange,
                        textLength: 3
                    )
            ) {
                try outOfBoundsSnapshot.nsAttributedString(
                    theme: .rorkDark
                )
            }
            #expect(
                throws:
                    HighlightRenderingError.invalidUTF16Boundary(
                        splitCharacterRange
                    )
            ) {
                try splitCharacterSnapshot.nsAttributedString(
                    theme: .rorkDark
                )
            }
        }

        /// Confirms the public method exposes only rendering domain failures.
        @Test
        func exposesTypedRenderingContract() throws(HighlightRenderingError) {
            let snapshot = makeSnapshot(text: "let value = 1")
            let render:
                (
                    HighlightTheme,
                    TestNativeFont
                ) throws(HighlightRenderingError) -> NSAttributedString =
                    snapshot.nsAttributedString(theme:font:)

            _ = try render(
                .rorkLight,
                .monospacedSystemFont(
                    ofSize: TestNativeFont.systemFontSize,
                    weight: .regular
                )
            )
        }

        /// Creates a deterministic snapshot for native rendering tests.
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

        /// Compares a native color attribute with a renderer-neutral color.
        ///
        /// - Parameters:
        ///   - value: The native attribute value to inspect.
        ///   - expectedColor: The expected renderer-neutral color.
        /// - Returns: `true` when every sRGB channel matches.
        private func color(
            _ value: Any?,
            matches expectedColor: HighlightColor
        ) -> Bool {
            guard let nativeColor = value as? TestNativeColor else {
                return false
            }

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            #if canImport(UIKit)
                guard
                    nativeColor.getRed(
                        &red,
                        green: &green,
                        blue: &blue,
                        alpha: &alpha
                    )
                else {
                    return false
                }
            #elseif canImport(AppKit)
                guard
                    let sRGBColor = nativeColor.usingColorSpace(
                        .sRGB
                    )
                else {
                    return false
                }
                sRGBColor.getRed(
                    &red,
                    green: &green,
                    blue: &blue,
                    alpha: &alpha
                )
            #endif

            let tolerance: CGFloat = 0.000_1
            return abs(red - CGFloat(expectedColor.red) / 255) < tolerance
                && abs(green - CGFloat(expectedColor.green) / 255) < tolerance
                && abs(blue - CGFloat(expectedColor.blue) / 255) < tolerance
                && abs(alpha - CGFloat(expectedColor.alpha) / 255) < tolerance
        }

        /// Returns whether a native font carries a bold symbolic trait.
        ///
        /// - Parameter font: The font to inspect.
        /// - Returns: `true` when the font has a bold face.
        private func fontIsBold(_ font: TestNativeFont) -> Bool {
            #if canImport(UIKit)
                font.fontDescriptor.symbolicTraits.contains(.traitBold)
            #elseif canImport(AppKit)
                font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        }

        /// Returns whether a native font carries an italic symbolic trait.
        ///
        /// - Parameter font: The font to inspect.
        /// - Returns: `true` when the font has an italic face.
        private func fontIsItalic(_ font: TestNativeFont) -> Bool {
            #if canImport(UIKit)
                font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            #elseif canImport(AppKit)
                font.fontDescriptor.symbolicTraits.contains(.italic)
            #endif
        }
    }
#endif
