#if canImport(UIKit)
    import UIKit

    /// Names the platform font used by the shared TextKit renderer.
    private typealias NativeHighlightFont = UIFont

    /// Names the platform color used by the shared TextKit renderer.
    private typealias NativeHighlightColor = UIColor

    /// Creates UIKit attributed output from immutable highlight snapshots.
    extension HighlightSnapshot {
        /// Renders the snapshot with UIKit attributes.
        ///
        /// Highlight spans are applied in their stored order so later spans can
        /// refine overlapping captures. The supplied font covers the complete
        /// source and provides the base face for bold and italic theme traits.
        ///
        /// - Parameters:
        ///   - theme: The theme used to resolve each capture scope.
        ///   - font: The base font used throughout the rendered source.
        /// - Returns: The complete source with native UIKit attributes.
        /// - Throws: ``HighlightRenderingError`` when a highlight range cannot be
        ///   represented by the snapshot text.
        public func nsAttributedString(
            theme: HighlightTheme,
            font: UIFont = .monospacedSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                weight: .regular
            )
        ) throws(HighlightRenderingError) -> NSAttributedString {
            try makeNSAttributedString(theme: theme, font: font)
        }
    }

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

    /// Names the platform font used by the shared TextKit renderer.
    private typealias NativeHighlightFont = NSFont

    /// Names the platform color used by the shared TextKit renderer.
    private typealias NativeHighlightColor = NSColor

    /// Creates AppKit attributed output from immutable highlight snapshots.
    extension HighlightSnapshot {
        /// Renders the snapshot with AppKit attributes.
        ///
        /// Highlight spans are applied in their stored order so later spans can
        /// refine overlapping captures. The supplied font covers the complete
        /// source and provides the base face for bold and italic theme traits.
        ///
        /// - Parameters:
        ///   - theme: The theme used to resolve each capture scope.
        ///   - font: The base font used throughout the rendered source.
        /// - Returns: The complete source with native AppKit attributes.
        /// - Throws: ``HighlightRenderingError`` when a highlight range cannot be
        ///   represented by the snapshot text.
        public func nsAttributedString(
            theme: HighlightTheme,
            font: NSFont = .monospacedSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            )
        ) throws(HighlightRenderingError) -> NSAttributedString {
            try makeNSAttributedString(theme: theme, font: font)
        }
    }

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
    /// Implements TextKit rendering shared by UIKit and AppKit.
    private extension HighlightSnapshot {
        /// Builds an immutable native attributed string after validating ranges.
        ///
        /// - Parameters:
        ///   - theme: The theme used to resolve each capture scope.
        ///   - font: The base platform font used throughout the source.
        /// - Returns: A native attributed copy of the complete source.
        /// - Throws: ``HighlightRenderingError`` when a highlight range cannot be
        ///   represented by the snapshot text.
        func makeNSAttributedString(
            theme: HighlightTheme,
            font: NativeHighlightFont
        ) throws(HighlightRenderingError) -> NSAttributedString {
            try validateHighlightRanges()

            var attributeCache = NativeHighlightAttributeCache(
                relativeTo: font
            )
            let baseAttributes = attributeCache.attributes(
                for: theme.baseStyle,
                includingBaseFont: true
            )
            let result = NSMutableAttributedString(
                string: text,
                attributes: baseAttributes.values
            )
            var styleCache = HighlightStyleCache(theme: theme)

            result.beginEditing()
            for highlight in highlights {
                result.apply(
                    attributeCache.attributes(
                        for: styleCache.style(for: highlight),
                        includingBaseFont: false
                    ),
                    to: NSRange(
                        location: highlight.range.location,
                        length: highlight.range.length
                    )
                )
            }
            result.endEditing()

            return NSAttributedString(attributedString: result)
        }
    }

    /// Caches native attributes derived from repeated renderer-neutral styles.
    private struct NativeHighlightAttributeCache {
        /// Holds the caller-provided base font.
        private let font: NativeHighlightFont

        /// Stores attributes that refine an existing base font.
        private var refinements: [HighlightStyle: NativeHighlightAttributes]

        /// Creates an empty attribute cache for one rendering operation.
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
        /// Holds values added together through TextKit.
        let values: [NSAttributedString.Key: Any]

        /// Records whether an inherited underline must be removed.
        let removesUnderline: Bool

        /// Records whether an inherited strikethrough must be removed.
        let removesStrikethrough: Bool
    }

    /// Applies resolved theme styles through TextKit attribute keys.
    private extension NSMutableAttributedString {
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
