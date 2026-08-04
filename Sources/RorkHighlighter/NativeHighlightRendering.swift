#if canImport(UIKit)
    import UIKit

    /// Names the platform font used by shared TextKit rendering code.
    typealias NativeHighlightFont = UIFont

    /// Names the platform color used by shared TextKit rendering code.
    private typealias NativeHighlightColor = UIColor

    /// Derives theme typography from a caller-provided UIKit font.
    private extension UIFont {
        /// Returns this font with the requested face traits.
        ///
        /// Underline and strikethrough traits are applied as separate attributed
        /// string values.
        ///
        /// - Parameter traits: The complete set of renderer-neutral text traits.
        /// - Returns: The font carrying bold and italic traits.
        func applying(
            _ traits: Set<HighlightTextTrait>
        ) -> UIFont {
            var symbolicTraits = fontDescriptor.symbolicTraits
            if traits.contains(.bold) {
                symbolicTraits.insert(.traitBold)
            }
            if traits.contains(.italic) {
                symbolicTraits.insert(.traitItalic)
            }
            guard
                let descriptor = fontDescriptor.withSymbolicTraits(
                    symbolicTraits
                )
            else {
                return self
            }
            return UIFont(descriptor: descriptor, size: pointSize)
        }
    }
#elseif canImport(AppKit)
    import AppKit

    /// Names the platform font used by shared TextKit rendering code.
    typealias NativeHighlightFont = NSFont

    /// Names the platform color used by shared TextKit rendering code.
    private typealias NativeHighlightColor = NSColor

    /// Derives theme typography from a caller-provided AppKit font.
    private extension NSFont {
        /// Returns this font with the requested face traits.
        ///
        /// Underline and strikethrough traits are applied as separate attributed
        /// string values.
        ///
        /// - Parameter traits: The complete set of renderer-neutral text traits.
        /// - Returns: The font carrying bold and italic traits.
        func applying(
            _ traits: Set<HighlightTextTrait>
        ) -> NSFont {
            var symbolicTraits = fontDescriptor.symbolicTraits
            if traits.contains(.bold) {
                symbolicTraits.insert(.bold)
            }
            if traits.contains(.italic) {
                symbolicTraits.insert(.italic)
            }
            let descriptor = fontDescriptor.withSymbolicTraits(
                symbolicTraits
            )
            return NSFont(
                descriptor: descriptor,
                size: pointSize
            ) ?? self
        }
    }
#endif

#if canImport(UIKit) || canImport(AppKit)
    /// Reuses resolved theme styles and platform attributes across edits.
    struct NativeHighlightRenderingContext {
        /// Caches native values derived from renderer-neutral styles.
        private var attributeCache: NativeHighlightAttributeCache

        /// Caches hierarchical theme resolution by capture components.
        private var styleCache: HighlightStyleCache

        /// Holds attributes restored before capture refinements are applied.
        private let baseAttributes: NativeHighlightAttributes

        /// Creates an empty rendering cache for one theme and base font.
        ///
        /// - Parameters:
        ///   - theme: The theme used to resolve capture scopes.
        ///   - font: The platform font used as the rendering baseline.
        init(
            theme: HighlightTheme,
            font: NativeHighlightFont
        ) {
            var attributeCache = NativeHighlightAttributeCache(
                relativeTo: font
            )
            self.baseAttributes = attributeCache.attributes(
                for: theme.baseStyle,
                includingBaseFont: true
            )
            self.attributeCache = attributeCache
            self.styleCache = HighlightStyleCache(theme: theme)
        }

        /// Restyles selected ranges without replacing the attributed string.
        ///
        /// Rendering ranges must be sorted, disjoint, and bounded to the
        /// snapshot source. Highlight spans remain in their stored precedence
        /// order while each one is clipped to the requested ranges.
        ///
        /// - Parameters:
        ///   - snapshot: The complete highlighting state being rendered.
        ///   - textStorage: The mutable attributed string receiving attributes.
        ///   - ranges: The sorted source ranges requiring new attributes.
        mutating func apply(
            _ snapshot: HighlightSnapshot,
            to textStorage: NSMutableAttributedString,
            in ranges: [UTF16Range]
        ) {
            for range in ranges {
                let nativeRange = NSRange(
                    location: range.location,
                    length: range.length
                )
                textStorage.resetHighlightAttributes(in: nativeRange)
                textStorage.apply(baseAttributes, to: nativeRange)
            }

            var firstCandidateRangeIndex = ranges.startIndex
            for highlight in snapshot.highlights {
                while firstCandidateRangeIndex < ranges.endIndex,
                    ranges[firstCandidateRangeIndex].upperBound
                        <= highlight.range.location
                {
                    firstCandidateRangeIndex += 1
                }
                guard firstCandidateRangeIndex < ranges.endIndex else {
                    break
                }

                var attributes: NativeHighlightAttributes?
                var rangeIndex = firstCandidateRangeIndex
                while rangeIndex < ranges.endIndex,
                    ranges[rangeIndex].location < highlight.range.upperBound
                {
                    let range = ranges[rangeIndex]
                    let lowerBound = max(
                        range.location,
                        highlight.range.location
                    )
                    let upperBound = min(
                        range.upperBound,
                        highlight.range.upperBound
                    )
                    if lowerBound < upperBound {
                        let resolvedAttributes: NativeHighlightAttributes
                        if let attributes {
                            resolvedAttributes = attributes
                        } else {
                            let newAttributes = attributeCache.attributes(
                                for: styleCache.style(for: highlight),
                                includingBaseFont: false
                            )
                            attributes = newAttributes
                            resolvedAttributes = newAttributes
                        }
                        textStorage.apply(
                            resolvedAttributes,
                            to: NSRange(
                                location: lowerBound,
                                length: upperBound - lowerBound
                            )
                        )
                    }
                    rangeIndex += 1
                }
            }
        }
    }

    /// Caches native attributes derived from repeated renderer-neutral styles.
    private struct NativeHighlightAttributeCache {
        /// Holds the caller-provided base font.
        private let font: NativeHighlightFont

        /// Stores attributes that refine an existing base font.
        private var refinements: [HighlightStyle: NativeHighlightAttributes]

        /// Creates an empty cache for one rendering configuration.
        ///
        /// - Parameter font: The base font used to derive text traits.
        init(relativeTo font: NativeHighlightFont) {
            self.font = font
            self.refinements = [:]
        }

        /// Returns cached native attributes for one resolved style.
        ///
        /// - Parameters:
        ///   - style: The renderer-neutral style to convert.
        ///   - includingBaseFont: Whether an otherwise absent font should be
        ///     included for the complete source range.
        /// - Returns: Native values and explicit line-style removals.
        mutating func attributes(
            for style: HighlightStyle,
            includingBaseFont: Bool
        ) -> NativeHighlightAttributes {
            if !includingBaseFont, let cached = refinements[style] {
                return cached
            }

            var values: [NSAttributedString.Key: Any] = [:]
            if includingBaseFont {
                values[.font] = font
            }
            if let foregroundColor = style.foregroundColor {
                values[.foregroundColor] =
                    foregroundColor.nativeHighlightColor
            }
            if let backgroundColor = style.backgroundColor {
                values[.backgroundColor] =
                    backgroundColor.nativeHighlightColor
            }

            let removesUnderline: Bool
            let removesStrikethrough: Bool
            if let textTraits = style.textTraits {
                values[.font] = font.applying(textTraits)
                if textTraits.contains(.underline) {
                    values[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    removesUnderline = false
                } else {
                    removesUnderline = true
                }
                if textTraits.contains(.strikethrough) {
                    values[.strikethroughStyle] =
                        NSUnderlineStyle.single.rawValue
                    removesStrikethrough = false
                } else {
                    removesStrikethrough = true
                }
            } else {
                removesUnderline = false
                removesStrikethrough = false
            }

            let attributes = NativeHighlightAttributes(
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

    /// Holds one reusable native attribute refinement.
    private struct NativeHighlightAttributes {
        /// Names every standard attribute managed by syntax rendering.
        static let managedKeys: [NSAttributedString.Key] = [
            .font,
            .foregroundColor,
            .backgroundColor,
            .underlineStyle,
            .strikethroughStyle,
        ]

        /// Holds values added together through TextKit.
        let values: [NSAttributedString.Key: Any]

        /// Records whether an inherited underline must be removed.
        let removesUnderline: Bool

        /// Records whether an inherited strikethrough must be removed.
        let removesStrikethrough: Bool
    }

    /// Applies resolved theme styles through TextKit attribute keys.
    private extension NSMutableAttributedString {
        /// Removes attributes owned by syntax rendering from a source range.
        ///
        /// - Parameter range: The UTF-16 range returning to the theme baseline.
        func resetHighlightAttributes(in range: NSRange) {
            for key in NativeHighlightAttributes.managedKeys {
                removeAttribute(key, range: range)
            }
        }

        /// Applies cached values and explicit line-style removals.
        ///
        /// - Parameters:
        ///   - attributes: The native refinement to apply.
        ///   - range: The UTF-16 range receiving the style.
        func apply(
            _ attributes: NativeHighlightAttributes,
            to range: NSRange
        ) {
            if !attributes.values.isEmpty {
                addAttributes(attributes.values, range: range)
            }
            if attributes.removesUnderline {
                removeAttribute(.underlineStyle, range: range)
            }
            if attributes.removesStrikethrough {
                removeAttribute(.strikethroughStyle, range: range)
            }
        }
    }

    /// Converts portable theme colors into native platform colors.
    private extension HighlightColor {
        /// Returns the equivalent native color in the sRGB color space.
        var nativeHighlightColor: NativeHighlightColor {
            #if canImport(UIKit)
                UIColor(
                    red: CGFloat(red) / 255,
                    green: CGFloat(green) / 255,
                    blue: CGFloat(blue) / 255,
                    alpha: CGFloat(alpha) / 255
                )
            #elseif canImport(AppKit)
                NSColor(
                    srgbRed: CGFloat(red) / 255,
                    green: CGFloat(green) / 255,
                    blue: CGFloat(blue) / 255,
                    alpha: CGFloat(alpha) / 255
                )
            #endif
        }
    }
#endif
