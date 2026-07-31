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
            result.font = font
            result.apply(
                theme.baseStyle,
                to: result.startIndex..<result.endIndex,
                relativeTo: font
            )

            let ranges = try attributedRanges(in: result)
            for (highlight, range) in zip(highlights, ranges) {
                result.apply(
                    theme.style(for: highlight),
                    to: range,
                    relativeTo: font
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

    /// Applies resolved theme styles to native attributed ranges.
    private extension AttributedString {
        /// Applies the values present in a style without clearing omitted colors.
        ///
        /// A present text trait set replaces typography completely. This makes an
        /// empty set capable of removing traits inherited from an earlier
        /// overlapping capture.
        ///
        /// - Parameters:
        ///   - style: The resolved renderer-neutral style.
        ///   - range: The attributed range receiving the style.
        ///   - font: The base font used to derive bold and italic faces.
        mutating func apply(
            _ style: HighlightStyle,
            to range: Range<Index>,
            relativeTo font: Font
        ) {
            if let foregroundColor = style.foregroundColor {
                self[range].foregroundColor = foregroundColor.swiftUIColor
            }
            if let backgroundColor = style.backgroundColor {
                self[range].backgroundColor = backgroundColor.swiftUIColor
            }
            if let textTraits = style.textTraits {
                self[range].font = font.applying(textTraits)
                self[range].underlineStyle =
                    textTraits.contains(.underline)
                    ? Text.LineStyle(pattern: .solid)
                    : nil
                self[range].strikethroughStyle =
                    textTraits.contains(.strikethrough)
                    ? Text.LineStyle(pattern: .solid)
                    : nil
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
