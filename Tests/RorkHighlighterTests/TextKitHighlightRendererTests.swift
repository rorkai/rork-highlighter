#if canImport(UIKit)
    import Testing
    import UIKit

    /// Names the UIKit font used by incremental rendering tests.
    private typealias TestTextKitFont = UIFont

    /// Names the UIKit color used by incremental rendering tests.
    private typealias TestTextKitColor = UIColor

    /// Names the UIKit edit action type used by TextKit delegates.
    private typealias TestTextStorageEditActions = NSTextStorage.EditActions
#elseif canImport(AppKit)
    import AppKit
    import Testing

    /// Names the AppKit font used by incremental rendering tests.
    private typealias TestTextKitFont = NSFont

    /// Names the AppKit color used by incremental rendering tests.
    private typealias TestTextKitColor = NSColor

    /// Names the AppKit edit action type used by TextKit delegates.
    private typealias TestTextStorageEditActions = NSTextStorageEditActions
#endif

#if canImport(UIKit) || canImport(AppKit)
    @testable import RorkHighlighter

    /// Verifies complete and incremental rendering into TextKit storage.
    @Suite
    @MainActor
    struct TextKitHighlightRendererTests {
        /// Names a caller-owned attribute that syntax rendering must preserve.
        private static let preservedAttribute = NSAttributedString.Key(
            "dev.rork.highlighter.tests.preserved"
        )

        /// Lists the standard attributes owned by syntax rendering.
        private static let managedAttributes: [NSAttributedString.Key] = [
            .font,
            .foregroundColor,
            .backgroundColor,
            .underlineStyle,
            .strikethroughStyle,
        ]

        /// Records the ranges TextKit processes after syntax attributes change.
        private final class TextStorageEditObserver: NSObject,
            NSTextStorageDelegate
        {
            /// Stores every processed attribute-edit range.
            var ranges: [NSRange] = []

            /// Records the range processed by one TextKit editing transaction.
            ///
            /// - Parameters:
            ///   - textStorage: The storage that finished processing changes.
            ///   - editedMask: The kinds of changes processed by TextKit.
            ///   - editedRange: The UTF-16 range processed by TextKit.
            ///   - delta: The character-length change in this transaction.
            func textStorage(
                _ textStorage: NSTextStorage,
                didProcessEditing editedMask: TestTextStorageEditActions,
                range editedRange: NSRange,
                changeInLength delta: Int
            ) {
                ranges.append(editedRange)
            }
        }

        /// Confirms complete rendering preserves caller-owned TextKit values.
        @Test
        func rendersCompleteSnapshotWithoutReplacingCallerAttributes() throws {
            let source = "let value = 1"
            let snapshot = try Highlighter().highlight(source, as: .swift)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 7
            let storage = NSTextStorage(
                string: source,
                attributes: [
                    .paragraphStyle: paragraphStyle,
                    Self.preservedAttribute: "preserved",
                ]
            )
            let font = TestTextKitFont.monospacedSystemFont(
                ofSize: 15,
                weight: .regular
            )
            let renderer = TextKitHighlightRenderer(
                theme: .rorkDark,
                font: font
            )

            try renderer.render(snapshot, in: storage)

            #expect(storage.string == source)
            #expect(
                storage.attribute(
                    Self.preservedAttribute,
                    at: 0,
                    effectiveRange: nil
                ) as? String == "preserved"
            )
            #expect(
                (storage.attribute(
                    .paragraphStyle,
                    at: 0,
                    effectiveRange: nil
                ) as? NSParagraphStyle)?.lineSpacing == 7
            )
            try expectManagedAttributes(
                in: storage,
                match: snapshot,
                theme: .rorkDark,
                font: font
            )
        }

        /// Confirms sequential Unicode and variable-width edits match a full
        /// render after every update.
        @Test
        func appliesSequentialEditsWithoutRebuildingAttributedText() async throws {
            let source = """
                let emoji = "😀"
                let value = 1000
                let enabled = true
                """
            let highlighter = try Highlighter()
            let session = try highlighter.makeSession(source, as: .swift)
            let snapshot = try await session.snapshot()
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.defaultTabInterval = 24
            let storage = NSTextStorage(
                string: source,
                attributes: [.paragraphStyle: paragraphStyle]
            )
            let font = TestTextKitFont.monospacedSystemFont(
                ofSize: 14,
                weight: .regular
            )
            let renderer = TextKitHighlightRenderer(
                theme: .rorkDark,
                font: font
            )
            try renderer.render(snapshot, in: storage)

            try await replace(
                "1000",
                with: #""many""#,
                in: storage,
                using: session,
                renderer: renderer,
                theme: .rorkDark,
                font: font
            )
            try await replace(
                "😀",
                with: "✨ Rork",
                in: storage,
                using: session,
                renderer: renderer,
                theme: .rorkDark,
                font: font
            )
            try await replace(
                "let value = \"many\"\n",
                with: "",
                in: storage,
                using: session,
                renderer: renderer,
                theme: .rorkDark,
                font: font
            )

            #expect(
                (storage.attribute(
                    .paragraphStyle,
                    at: 0,
                    effectiveRange: nil
                ) as? NSParagraphStyle)?.defaultTabInterval == 24
            )
        }

        /// Confirms a zero-length insertion expands an existing capture without
        /// disturbing attributes owned by the text view.
        @Test
        func appliesInsertionAtCaptureBoundary() async throws {
            let source = "let title = \"Rork\""
            let highlighter = try Highlighter()
            let session = try highlighter.makeSession(source, as: .swift)
            let snapshot = try await session.snapshot()
            let storage = NSTextStorage(
                string: source,
                attributes: [Self.preservedAttribute: "preserved"]
            )
            let font = TestTextKitFont.monospacedSystemFont(
                ofSize: 14,
                weight: .regular
            )
            let renderer = TextKitHighlightRenderer(
                theme: .rorkDark,
                font: font
            )
            try renderer.render(snapshot, in: storage)

            let titleRange = (storage.string as NSString).range(of: "Rork")
            let insertionRange = NSRange(
                location: titleRange.upperBound,
                length: 0
            )
            let insertion = " Highlighter"
            storage.replaceCharacters(in: insertionRange, with: insertion)
            let update = try await session.replaceCharacters(
                in: UTF16Range(
                    location: insertionRange.location,
                    length: insertionRange.length
                ),
                with: insertion
            )

            try renderer.render(update, in: storage)

            try expectManagedAttributes(
                in: storage,
                match: update.snapshot,
                theme: .rorkDark,
                font: font
            )
            #expect(
                storage.attribute(
                    Self.preservedAttribute,
                    at: insertionRange.location,
                    effectiveRange: nil
                ) as? String == "preserved"
            )
        }

        /// Confirms the incremental fast path does not process the complete
        /// attributed document after a local edit.
        @Test
        func processesOnlyTheInvalidatedTextKitRegion() async throws {
            let source = (0..<200)
                .map { "let value\($0) = \($0)" }
                .joined(separator: "\n")
            let highlighter = try Highlighter()
            let session = try highlighter.makeSession(source, as: .swift)
            let snapshot = try await session.snapshot()
            let storage = NSTextStorage(string: source)
            let renderer = TextKitHighlightRenderer(theme: .rorkDark)
            try renderer.render(snapshot, in: storage)

            let editRange = (storage.string as NSString).range(
                of: "value100"
            )
            storage.replaceCharacters(in: editRange, with: "result10")
            let update = try await session.replaceCharacters(
                in: UTF16Range(editRange.location..<editRange.upperBound),
                with: "result10"
            )
            let observer = TextStorageEditObserver()
            storage.delegate = observer

            try renderer.render(update, in: storage)
            storage.delegate = nil

            let processedRange = observer.ranges.reduce(
                NSRange(location: NSNotFound, length: 0)
            ) { partialResult, range in
                guard partialResult.location != NSNotFound else {
                    return range
                }
                return NSUnionRange(partialResult, range)
            }
            #expect(processedRange.location != NSNotFound)
            #expect(processedRange.length < storage.length)
            #expect(NSLocationInRange(editRange.location, processedRange))
        }

        /// Confirms a skipped update falls back to a verified complete render.
        @Test
        func resynchronizesAfterSkippedRevision() async throws {
            let source = """
                let first = 1000
                let second = 2000
                """
            let highlighter = try Highlighter()
            let session = try highlighter.makeSession(source, as: .swift)
            let snapshot = try await session.snapshot()
            let storage = NSTextStorage(string: source)
            let font = TestTextKitFont.monospacedSystemFont(
                ofSize: 14,
                weight: .regular
            )
            let renderer = TextKitHighlightRenderer(
                theme: .rorkLight,
                font: font
            )
            try renderer.render(snapshot, in: storage)

            let firstRange = (storage.string as NSString).range(of: "1000")
            storage.replaceCharacters(in: firstRange, with: "3000")
            _ = try await session.replaceCharacters(
                in: UTF16Range(firstRange.location..<firstRange.upperBound),
                with: "3000"
            )

            let secondRange = (storage.string as NSString).range(of: "2000")
            storage.replaceCharacters(in: secondRange, with: "4000")
            let latestUpdate = try await session.replaceCharacters(
                in: UTF16Range(secondRange.location..<secondRange.upperBound),
                with: "4000"
            )
            storage.addAttribute(
                .foregroundColor,
                value: TestTextKitColor.red,
                range: NSRange(location: 0, length: 1)
            )

            try renderer.render(latestUpdate, in: storage)

            try expectManagedAttributes(
                in: storage,
                match: latestUpdate.snapshot,
                theme: .rorkLight,
                font: font
            )
        }

        /// Confirms changing storage falls back to a verified complete render.
        @Test
        func resynchronizesWhenTextStorageChanges() async throws {
            let source = "let value = 1000"
            let highlighter = try Highlighter()
            let session = try highlighter.makeSession(source, as: .swift)
            let snapshot = try await session.snapshot()
            let originalStorage = NSTextStorage(string: source)
            let font = TestTextKitFont.monospacedSystemFont(
                ofSize: 14,
                weight: .regular
            )
            let renderer = TextKitHighlightRenderer(
                theme: .rorkDark,
                font: font
            )
            try renderer.render(snapshot, in: originalStorage)

            let numberRange = (source as NSString).range(of: "1000")
            let update = try await session.replaceCharacters(
                in: UTF16Range(numberRange.location..<numberRange.upperBound),
                with: "2000"
            )
            let replacementStorage = NSTextStorage(
                string: update.snapshot.text,
                attributes: [.foregroundColor: TestTextKitColor.red]
            )

            try renderer.render(update, in: replacementStorage)

            try expectManagedAttributes(
                in: replacementStorage,
                match: update.snapshot,
                theme: .rorkDark,
                font: font
            )
        }

        /// Confirms changing configuration resynchronizes the complete document.
        @Test
        func resynchronizesAfterThemeAndFontChange() async throws {
            let source = "let value = 1000"
            let highlighter = try Highlighter()
            let session = try highlighter.makeSession(source, as: .swift)
            let snapshot = try await session.snapshot()
            let storage = NSTextStorage(string: source)
            let renderer = TextKitHighlightRenderer(theme: .rorkDark)
            try renderer.render(snapshot, in: storage)

            let updatedFont = TestTextKitFont.monospacedSystemFont(
                ofSize: 18,
                weight: .bold
            )
            renderer.theme = .rorkLight
            renderer.font = updatedFont
            let numberRange = (storage.string as NSString).range(of: "1000")
            storage.replaceCharacters(in: numberRange, with: "2000")
            let update = try await session.replaceCharacters(
                in: UTF16Range(numberRange.location..<numberRange.upperBound),
                with: "2000"
            )

            try renderer.render(update, in: storage)

            try expectManagedAttributes(
                in: storage,
                match: update.snapshot,
                theme: .rorkLight,
                font: updatedFont
            )
        }

        /// Confirms a mismatched source fails before TextKit attributes change.
        @Test
        func rejectsMismatchedTextStorageWithoutMutation() throws {
            let snapshot = HighlightSnapshot(
                text: "let one = 1",
                language: .swift,
                revision: 7,
                highlights: []
            )
            let storage = NSTextStorage(
                string: "let two = 2",
                attributes: [Self.preservedAttribute: "untouched"]
            )
            let renderer = TextKitHighlightRenderer(theme: .rorkDark)

            #expect(
                throws:
                    HighlightRenderingError.textStorageMismatch(
                        snapshotRevision: 7,
                        expectedLength: snapshot.text.utf16.count,
                        actualLength: storage.length
                    )
            ) {
                try renderer.render(snapshot, in: storage)
            }
            #expect(storage.string == "let two = 2")
            #expect(
                storage.attribute(
                    Self.preservedAttribute,
                    at: 0,
                    effectiveRange: nil
                ) as? String == "untouched"
            )
            #expect(
                storage.attribute(
                    .foregroundColor,
                    at: 0,
                    effectiveRange: nil
                ) == nil
            )
        }

        /// Confirms both public methods expose rendering-domain failures only.
        @Test
        func exposesTypedRenderingContracts() throws(HighlightRenderingError) {
            let snapshot = HighlightSnapshot(
                text: "let value = 1",
                language: .swift,
                revision: 0,
                highlights: []
            )
            let storage = NSTextStorage(string: snapshot.text)
            let renderer = TextKitHighlightRenderer(theme: .rorkDark)
            let renderSnapshot:
                (
                    HighlightSnapshot,
                    NSTextStorage
                ) throws(HighlightRenderingError) -> Void = renderer.render(_:in:)
            let renderUpdate:
                (
                    HighlightUpdate,
                    NSTextStorage
                ) throws(HighlightRenderingError) -> Void = renderer.render(_:in:)

            try renderSnapshot(snapshot, storage)
            _ = renderUpdate
        }

        /// Applies one text edit and compares incremental attributes with a full
        /// immutable render.
        ///
        /// - Parameters:
        ///   - target: The unique source fragment being replaced.
        ///   - replacement: The source text inserted in its place.
        ///   - textStorage: The TextKit storage receiving the character edit.
        ///   - session: The incremental parser receiving the same edit.
        ///   - renderer: The renderer applying the returned invalidation ranges.
        ///   - theme: The theme shared by incremental and complete rendering.
        ///   - font: The font shared by incremental and complete rendering.
        /// - Throws: Highlighting or rendering failures from either path.
        private func replace(
            _ target: String,
            with replacement: String,
            in textStorage: NSTextStorage,
            using session: HighlightSession,
            renderer: TextKitHighlightRenderer,
            theme: HighlightTheme,
            font: TestTextKitFont
        ) async throws {
            let range = (textStorage.string as NSString).range(of: target)
            guard range.location != NSNotFound else {
                Issue.record("Expected the edit target in TextKit storage.")
                return
            }

            textStorage.replaceCharacters(in: range, with: replacement)
            let update = try await session.replaceCharacters(
                in: UTF16Range(range.location..<range.upperBound),
                with: replacement
            )
            try renderer.render(update, in: textStorage)
            #expect(textStorage.string == update.snapshot.text)
            try expectManagedAttributes(
                in: textStorage,
                match: update.snapshot,
                theme: theme,
                font: font
            )
        }

        /// Compares every syntax-owned TextKit value with a complete render.
        ///
        /// - Parameters:
        ///   - textStorage: The incrementally rendered TextKit storage.
        ///   - snapshot: The snapshot used to build the complete control value.
        ///   - theme: The theme shared by both rendering paths.
        ///   - font: The font shared by both rendering paths.
        /// - Throws: ``HighlightRenderingError`` when the control cannot render.
        private func expectManagedAttributes(
            in textStorage: NSTextStorage,
            match snapshot: HighlightSnapshot,
            theme: HighlightTheme,
            font: TestTextKitFont
        ) throws(HighlightRenderingError) {
            let control = try snapshot.nsAttributedString(
                theme: theme,
                font: font
            )
            #expect(textStorage.string == control.string)
            #expect(textStorage.length == control.length)

            for location in 0..<textStorage.length {
                for key in Self.managedAttributes {
                    if key == .font,
                        textContainsEmoji(
                            snapshot.text,
                            atUTF16Location: location
                        )
                    {
                        continue
                    }
                    #expect(
                        nativeValuesAreEqual(
                            textStorage.attribute(
                                key,
                                at: location,
                                effectiveRange: nil
                            ),
                            control.attribute(
                                key,
                                at: location,
                                effectiveRange: nil
                            )
                        )
                    )
                }
            }
        }

        /// Returns whether a UTF-16 location belongs to an emoji grapheme.
        ///
        /// TextKit may replace the requested font with its native color-emoji
        /// fallback while processing an otherwise unrelated character edit.
        ///
        /// - Parameters:
        ///   - text: The complete source string containing the location.
        ///   - location: The UTF-16 location to inspect.
        /// - Returns: `true` when the enclosing grapheme contains emoji data.
        private func textContainsEmoji(
            _ text: String,
            atUTF16Location location: Int
        ) -> Bool {
            let nativeText = text as NSString
            let characterRange = nativeText.rangeOfComposedCharacterSequence(
                at: location
            )
            let character = nativeText.substring(with: characterRange)
            return character.unicodeScalars.contains {
                $0.properties.isEmoji
            }
        }

        /// Compares two optional native attributed-string values.
        ///
        /// - Parameters:
        ///   - lhs: The incrementally rendered value.
        ///   - rhs: The completely rendered control value.
        /// - Returns: `true` when both values are absent or natively equal.
        private func nativeValuesAreEqual(
            _ lhs: Any?,
            _ rhs: Any?
        ) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil):
                true
            case (let lhs as NSObject, let rhs as NSObject):
                lhs.isEqual(rhs)
            default:
                false
            }
        }
    }
#endif
