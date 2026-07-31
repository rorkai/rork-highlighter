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
                ofSize: UIFont.systemFontSize,
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

            let completeRange = NSRange(
                location: 0,
                length: text.utf16.count
            )
            let result = NSMutableAttributedString(string: text)
            result.addAttribute(
                .font,
                value: font as AnyObject,
                range: completeRange
            )
            result.apply(
                theme.baseStyle,
                to: completeRange,
                relativeTo: font
            )

            for highlight in highlights {
                result.apply(
                    theme.style(for: highlight),
                    to: NSRange(
                        location: highlight.range.location,
                        length: highlight.range.length
                    ),
                    relativeTo: font
                )
            }

            return NSAttributedString(attributedString: result)
        }
    }

    /// Applies resolved theme styles through TextKit attribute keys.
    private extension NSMutableAttributedString {
        /// Applies present colors and replaces typography when traits are present.
        ///
        /// - Parameters:
        ///   - style: The resolved renderer-neutral style.
        ///   - range: The UTF-16 range receiving the style.
        ///   - font: The base font used to derive bold and italic faces.
        func apply(
            _ style: HighlightStyle,
            to range: NSRange,
            relativeTo font: NativeHighlightFont
        ) {
            if let foregroundColor = style.foregroundColor {
                addAttribute(
                    .foregroundColor,
                    value:
                        foregroundColor.nativeHighlightColor
                        as AnyObject,
                    range: range
                )
            }
            if let backgroundColor = style.backgroundColor {
                addAttribute(
                    .backgroundColor,
                    value:
                        backgroundColor.nativeHighlightColor
                        as AnyObject,
                    range: range
                )
            }
            if let textTraits = style.textTraits {
                addAttribute(
                    .font,
                    value: font.applying(textTraits) as AnyObject,
                    range: range
                )
                applyLineStyle(
                    .underlineStyle,
                    when: textTraits.contains(.underline),
                    to: range
                )
                applyLineStyle(
                    .strikethroughStyle,
                    when: textTraits.contains(.strikethrough),
                    to: range
                )
            }
        }

        /// Adds or removes one TextKit line style over a range.
        ///
        /// Removing the key allows an explicit empty trait set to clear an earlier
        /// overlapping capture.
        ///
        /// - Parameters:
        ///   - key: The underline or strikethrough attribute key.
        ///   - isEnabled: Whether the line should be visible.
        ///   - range: The UTF-16 range receiving the change.
        func applyLineStyle(
            _ key: NSAttributedString.Key,
            when isEnabled: Bool,
            to range: NSRange
        ) {
            if isEnabled {
                addAttribute(
                    key,
                    value: NSNumber(
                        value: NSUnderlineStyle.single.rawValue
                    ),
                    range: range
                )
            } else {
                removeAttribute(key, range: range)
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
