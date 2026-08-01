#if canImport(SwiftUI)
    import Foundation
    import SwiftUI

    /// Creates native attributed output from immutable highlight snapshots.
    extension HighlightSnapshot {
        /// Renders the snapshot with SwiftUI attributes.
        ///
        /// Highlight spans are applied in their stored order so later spans can
        /// refine overlapping captures. The supplied font covers the complete
        /// source and provides the base face for bold and italic theme traits.
        ///
        /// - Parameters:
        ///   - theme: The theme used to resolve each capture scope.
        ///   - font: The base font used throughout the rendered source.
        /// - Returns: The complete source with native SwiftUI attributes.
        /// - Throws: ``HighlightRenderingError`` when a highlight range cannot be
        ///   represented by the snapshot text.
        public func attributedString(
            theme: HighlightTheme,
            font: Font = .system(.body, design: .monospaced)
        ) throws(HighlightRenderingError) -> AttributedString {
            var result = AttributedString(text)
            var attributeCache = SwiftUIHighlightAttributeCache(
                relativeTo: font
            )
            result.setAttributes(
                attributeCache.attributes(
                    for: theme.baseStyle,
                    includingBaseFont: true
                ).values
            )

            let ranges = try attributedRanges(in: result)
            var styleCache = HighlightStyleCache(theme: theme)
            for (highlight, range) in zip(highlights, ranges) {
                result.apply(
                    attributeCache.attributes(
                        for: styleCache.style(for: highlight),
                        includingBaseFont: false
                    ),
                    to: range
                )
            }

            return result
        }

        /// Converts every highlight range while sharing boundary indices.
        ///
        /// The conversion advances through the UTF-16 view once. Reusing indices
        /// avoids rescanning the source for every capture in a large document.
        ///
        /// - Parameter attributedString: The attributed copy of ``text``.
        /// - Returns: Attributed ranges in the same order as ``highlights``.
        /// - Throws: ``HighlightRenderingError`` when a range is outside the text
        ///   or does not align with Swift character boundaries.
        private func attributedRanges(
            in attributedString: AttributedString
        ) throws(HighlightRenderingError) -> [Range<AttributedString.Index>] {
            let textIndices = try validatedTextIndicesForHighlights()
            var attributedIndices: [Int: AttributedString.Index] = [:]
            attributedIndices.reserveCapacity(textIndices.count)

            for (offset, textIndex) in textIndices {
                if let attributedIndex = AttributedString.Index(
                    textIndex,
                    within: attributedString
                ) {
                    attributedIndices[offset] = attributedIndex
                }
            }

            var ranges: [Range<AttributedString.Index>] = []
            ranges.reserveCapacity(highlights.count)
            for highlight in highlights {
                guard
                    let lowerBound =
                        attributedIndices[highlight.range.location],
                    let upperBound =
                        attributedIndices[highlight.range.upperBound]
                else {
                    throw HighlightRenderingError.invalidUTF16Boundary(
                        highlight.range
                    )
                }
                ranges.append(lowerBound..<upperBound)
            }
            return ranges
        }
    }

    /// Caches SwiftUI attributes derived from repeated resolved styles.
    private struct SwiftUIHighlightAttributeCache {
        /// Holds the caller-provided base font.
        private let font: Font

        /// Stores refinements that build on the complete source attributes.
        private var refinements: [HighlightStyle: SwiftUIHighlightAttributes]

        /// Creates an empty attribute cache for one rendering operation.
        ///
        /// - Parameter font: The base font used to derive text traits.
        init(relativeTo font: Font) {
            self.font = font
            self.refinements = [:]
        }

        /// Returns cached SwiftUI attributes for one resolved style.
        ///
        /// - Parameters:
        ///   - style: The renderer-neutral style to convert.
        ///   - includingBaseFont: Whether an otherwise absent font should be
        ///     included for the complete source range.
        /// - Returns: Native values and explicit line-style removals.
        mutating func attributes(
            for style: HighlightStyle,
            includingBaseFont: Bool
        ) -> SwiftUIHighlightAttributes {
            if !includingBaseFont, let cached = refinements[style] {
                return cached
            }

            var values = AttributeContainer()
            if includingBaseFont {
                values.font = font
            }
            if let foregroundColor = style.foregroundColor {
                values.foregroundColor = foregroundColor.swiftUIColor
            }
            if let backgroundColor = style.backgroundColor {
                values.backgroundColor = backgroundColor.swiftUIColor
            }

            let removesUnderline: Bool
            let removesStrikethrough: Bool
            if let textTraits = style.textTraits {
                values.font = font.applying(textTraits)
                if textTraits.contains(.underline) {
                    values.underlineStyle = Text.LineStyle(pattern: .solid)
                    removesUnderline = false
                } else {
                    removesUnderline = true
                }
                if textTraits.contains(.strikethrough) {
                    values.strikethroughStyle = Text.LineStyle(
                        pattern: .solid
                    )
                    removesStrikethrough = false
                } else {
                    removesStrikethrough = true
                }
            } else {
                removesUnderline = false
                removesStrikethrough = false
            }

            let attributes = SwiftUIHighlightAttributes(
                values: values,
                removesUnderline: removesUnderline,
                removesStrikethrough: removesStrikethrough
            )
            if !includingBaseFont {
                refinements[style] = attributes
            }
            return attributes
        }
    }

    /// Holds one reusable SwiftUI attribute refinement.
    private struct SwiftUIHighlightAttributes {
        /// Holds values merged together on an attributed range.
        let values: AttributeContainer

        /// Records whether an inherited underline must be removed.
        let removesUnderline: Bool

        /// Records whether an inherited strikethrough must be removed.
        let removesStrikethrough: Bool
    }

    /// Applies resolved theme styles to native attributed ranges.
    private extension AttributedString {
        /// Applies cached values and explicit line-style removals.
        ///
        /// - Parameters:
        ///   - attributes: The SwiftUI refinement to apply.
        ///   - range: The attributed range receiving the style.
        mutating func apply(
            _ attributes: SwiftUIHighlightAttributes,
            to range: Range<Index>
        ) {
            self[range].mergeAttributes(attributes.values)
            if attributes.removesUnderline {
                self[range].underlineStyle = nil
            }
            if attributes.removesStrikethrough {
                self[range].strikethroughStyle = nil
            }
        }
    }

    /// Converts portable theme colors into SwiftUI colors.
    private extension HighlightColor {
        /// Returns the equivalent color in the sRGB color space.
        var swiftUIColor: Color {
            Color(
                .sRGB,
                red: Double(red) / 255,
                green: Double(green) / 255,
                blue: Double(blue) / 255,
                opacity: Double(alpha) / 255
            )
        }
    }

    /// Derives theme typography from a caller-provided SwiftUI font.
    private extension Font {
        /// Returns this font with the requested face traits.
        ///
        /// Underline and strikethrough traits are applied as separate attributed
        /// string values.
        ///
        /// - Parameter traits: The complete set of renderer-neutral text traits.
        /// - Returns: The font carrying bold and italic traits.
        func applying(_ traits: Set<HighlightTextTrait>) -> Self {
            var result = self
            if traits.contains(.bold) {
                result = result.bold()
            }
            if traits.contains(.italic) {
                result = result.italic()
            }
            return result
        }
    }
#endif
