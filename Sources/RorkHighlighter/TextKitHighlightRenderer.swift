#if canImport(UIKit)
    import UIKit

    /// Supplies UIKit configuration for incremental TextKit rendering.
    extension TextKitHighlightRenderer {
        /// Creates a renderer with a configured theme and UIKit base font.
        ///
        /// - Parameters:
        ///   - theme: The theme used to resolve capture scopes.
        ///   - font: The base font used throughout rendered source text.
        public convenience init(
            theme: HighlightTheme,
            font: UIFont = .monospacedSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                weight: .regular
            )
        ) {
            self.init(theme: theme, nativeFont: font)
        }

        /// Holds the UIKit font used as the rendering baseline.
        ///
        /// Assigning another font clears the cached document state. Render a
        /// complete snapshot before applying another incremental update.
        public var font: UIFont {
            get {
                nativeFont
            }
            set {
                nativeFont = newValue
                resetRenderingState()
            }
        }
    }
#elseif canImport(AppKit)
    import AppKit

    /// Supplies AppKit configuration for incremental TextKit rendering.
    extension TextKitHighlightRenderer {
        /// Creates a renderer with a configured theme and AppKit base font.
        ///
        /// - Parameters:
        ///   - theme: The theme used to resolve capture scopes.
        ///   - font: The base font used throughout rendered source text.
        public convenience init(
            theme: HighlightTheme,
            font: NSFont = .monospacedSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            )
        ) {
            self.init(theme: theme, nativeFont: font)
        }

        /// Holds the AppKit font used as the rendering baseline.
        ///
        /// Assigning another font clears the cached document state. Render a
        /// complete snapshot before applying another incremental update.
        public var font: NSFont {
            get {
                nativeFont
            }
            set {
                nativeFont = newValue
                resetRenderingState()
            }
        }
    }
#endif

#if canImport(UIKit) || canImport(AppKit)
    /// Applies complete snapshots and incremental updates to TextKit storage.
    ///
    /// The renderer retains resolved theme styles and native font faces across
    /// edits. It changes only font, foreground, background, underline, and
    /// strikethrough attributes, so paragraph styles and custom attributes stay
    /// under the caller's control.
    ///
    /// Instances contain mutable caches and do not conform to `Sendable`. Use a
    /// renderer on the same isolation domain that owns its `NSTextStorage`, and
    /// keep one renderer with each storage instance.
    public final class TextKitHighlightRenderer {
        /// Holds the theme used to resolve capture scopes.
        ///
        /// Assigning another theme clears the cached document state. Render a
        /// complete snapshot before applying another incremental update.
        public var theme: HighlightTheme {
            didSet {
                resetRenderingState()
            }
        }

        /// Holds the platform font used as the rendering baseline.
        fileprivate var nativeFont: NativeHighlightFont

        /// Reuses resolved native attributes while the configuration is stable.
        private var renderingContext: NativeHighlightRenderingContext

        /// Records the document revision represented by the TextKit storage.
        private var renderedDocument: TextKitRenderedDocument?

        /// Retains no ownership while identifying the rendered TextKit storage.
        private weak var renderedTextStorage: NSTextStorage?

        /// Creates a renderer from platform-neutral and platform-native values.
        ///
        /// Platform-specific public initializers supply `UIFont` or `NSFont`.
        ///
        /// - Parameters:
        ///   - theme: The theme used to resolve capture scopes.
        ///   - nativeFont: The platform font used as the rendering baseline.
        fileprivate init(
            theme: HighlightTheme,
            nativeFont: NativeHighlightFont
        ) {
            self.theme = theme
            self.nativeFont = nativeFont
            self.renderingContext = NativeHighlightRenderingContext(
                theme: theme,
                font: nativeFont
            )
            self.renderedDocument = nil
            self.renderedTextStorage = nil
        }

        /// Applies a complete snapshot to existing TextKit storage.
        ///
        /// The storage must already contain the snapshot source. Rendering
        /// replaces only attributes owned by syntax highlighting and preserves
        /// paragraph styles, attachments, links, and custom attributes.
        ///
        /// - Parameters:
        ///   - snapshot: The complete highlighting state to render.
        ///   - textStorage: The TextKit storage containing `snapshot.text`.
        /// - Throws: ``HighlightRenderingError`` when a range is invalid or the
        ///   storage does not contain the snapshot source.
        public func render(
            _ snapshot: HighlightSnapshot,
            in textStorage: NSTextStorage
        ) throws(HighlightRenderingError) {
            try snapshot.validateHighlightRanges()
            guard textStorage.string == snapshot.text else {
                throw HighlightRenderingError.textStorageMismatch(
                    snapshotRevision: snapshot.revision,
                    expectedLength: snapshot.utf16Length,
                    actualLength: textStorage.length
                )
            }

            let completeRange = UTF16Range(
                location: 0,
                length: snapshot.utf16Length
            )
            let renderingRanges =
                completeRange.length == 0 ? [] : [completeRange]

            textStorage.beginEditing()
            renderingContext.apply(
                snapshot,
                to: textStorage,
                in: renderingRanges
            )
            textStorage.endEditing()
            renderedDocument = TextKitRenderedDocument(snapshot: snapshot)
            renderedTextStorage = textStorage
        }

        /// Applies one incremental update to existing TextKit storage.
        ///
        /// Apply the same character edit to `textStorage` before calling this
        /// method. Updates must arrive in document revision order. The renderer
        /// avoids a complete source comparison on that fast path so large
        /// documents retain their incremental behavior.
        ///
        /// A skipped revision, another storage instance, or incompatible edit
        /// metadata triggers a verified complete render. This safely
        /// resynchronizes the renderer when the storage already contains the
        /// latest snapshot source.
        ///
        /// - Parameters:
        ///   - update: The highlighting update matching the applied text edit.
        ///   - textStorage: The storage containing `update.snapshot.text`.
        /// - Throws: ``HighlightRenderingError`` when a range is invalid or a
        ///   required complete render finds different source text.
        public func render(
            _ update: HighlightUpdate,
            in textStorage: NSTextStorage
        ) throws(HighlightRenderingError) {
            try update.snapshot.validateHighlightRanges()
            guard
                let renderingRanges = incrementalRenderingRanges(
                    for: update,
                    in: textStorage
                )
            else {
                try render(update.snapshot, in: textStorage)
                return
            }

            textStorage.beginEditing()
            renderingContext.apply(
                update.snapshot,
                to: textStorage,
                in: renderingRanges
            )
            textStorage.endEditing()
            renderedDocument = TextKitRenderedDocument(
                snapshot: update.snapshot
            )
            renderedTextStorage = textStorage
        }

        /// Returns merged new-document ranges for a compatible update.
        ///
        /// Returning `nil` asks the caller to verify and render the complete
        /// snapshot. Incremental rendering checks lengths and revisions without
        /// rescanning the complete source string.
        ///
        /// - Parameters:
        ///   - update: The update being matched with renderer state.
        ///   - textStorage: The storage after the corresponding character edit.
        /// - Returns: Sorted rendering ranges, or `nil` when state must be
        ///   resynchronized.
        private func incrementalRenderingRanges(
            for update: HighlightUpdate,
            in textStorage: NSTextStorage
        ) -> [UTF16Range]? {
            let snapshot = update.snapshot
            guard
                let renderedDocument,
                renderedTextStorage === textStorage,
                renderedDocument.revision < UInt64.max,
                snapshot.revision == renderedDocument.revision + 1,
                snapshot.language == renderedDocument.language,
                update.replacedRange.upperBound
                    <= renderedDocument.utf16Length,
                update.replacementRange.location
                    == update.replacedRange.location,
                renderedDocument.utf16Length - update.replacedRange.length
                    <= Int.max - update.replacementRange.length
            else {
                return nil
            }

            let updatedLength =
                renderedDocument.utf16Length
                - update.replacedRange.length
                + update.replacementRange.length
            guard
                updatedLength == snapshot.utf16Length,
                textStorage.length == updatedLength,
                update.replacementRange.upperBound <= updatedLength,
                update.invalidatedRanges.allSatisfy({
                    $0.upperBound <= updatedLength
                })
            else {
                return nil
            }

            return Self.mergedRenderingRanges(
                update.invalidatedRanges + [update.replacementRange]
            )
        }

        /// Merges overlapping and adjacent nonempty rendering ranges.
        ///
        /// - Parameter ranges: The bounded new-document ranges to merge.
        /// - Returns: Sorted disjoint ranges suitable for one TextKit edit.
        private static func mergedRenderingRanges(
            _ ranges: [UTF16Range]
        ) -> [UTF16Range] {
            let sortedRanges = ranges.filter { $0.length > 0 }.sorted()
            guard var currentRange = sortedRanges.first else {
                return []
            }

            var result: [UTF16Range] = []
            result.reserveCapacity(sortedRanges.count)
            for range in sortedRanges.dropFirst() {
                if range.location <= currentRange.upperBound {
                    currentRange = UTF16Range(
                        location: currentRange.location,
                        length:
                            max(currentRange.upperBound, range.upperBound)
                            - currentRange.location
                    )
                } else {
                    result.append(currentRange)
                    currentRange = range
                }
            }
            result.append(currentRange)
            return result
        }

        /// Rebuilds style caches and forgets the rendered document revision.
        fileprivate func resetRenderingState() {
            renderingContext = NativeHighlightRenderingContext(
                theme: theme,
                font: nativeFont
            )
            renderedDocument = nil
            renderedTextStorage = nil
        }
    }

    /// Identifies the snapshot currently represented by TextKit storage.
    private struct TextKitRenderedDocument {
        /// Identifies the root language whose attributes were rendered.
        let language: LanguageID

        /// Identifies the rendered snapshot revision.
        let revision: UInt64

        /// Holds the rendered source length in TextKit coordinates.
        let utf16Length: Int

        /// Creates state from a successfully rendered snapshot.
        ///
        /// - Parameter snapshot: The snapshot represented by the storage.
        init(snapshot: HighlightSnapshot) {
            self.language = snapshot.language
            self.revision = snapshot.revision
            self.utf16Length = snapshot.utf16Length
        }
    }
#endif
