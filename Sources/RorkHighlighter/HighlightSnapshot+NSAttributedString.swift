#if canImport(UIKit)
    import UIKit

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
#elseif canImport(AppKit)
    import AppKit

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
#endif

#if canImport(UIKit) || canImport(AppKit)
    /// Implements immutable native attributed output through the shared cache.
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

            let result = NSMutableAttributedString(string: text)
            let completeRange = UTF16Range(
                location: 0,
                length: utf16Length
            )
            var renderingContext = NativeHighlightRenderingContext(
                theme: theme,
                font: font
            )

            result.beginEditing()
            renderingContext.apply(
                self,
                to: result,
                in: completeRange.length == 0 ? [] : [completeRange]
            )
            result.endEditing()
            return NSAttributedString(attributedString: result)
        }
    }
#endif
