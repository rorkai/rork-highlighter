import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

/// Owns the mutable parse state for one changing document.
///
/// Actor isolation serializes edits and protects Tree-sitter's mutable parser
/// state. Callers may retain one session per open document and submit edits
/// from independent tasks without adding their own lock.
public actor HighlightSession {
    /// Holds immutable configuration and query-conversion helpers.
    private let highlighter: Highlighter

    /// Holds the canonical language definition selected at creation.
    private let languageDefinition: HighlightLanguage

    /// Identifies the canonical root language selected at creation.
    public nonisolated let language: LanguageID

    /// Holds the mutable Tree-sitter parse tree and nested language layers.
    private let layer: LanguageLayer

    /// Holds the source text represented by `layer`.
    private var text: String

    /// Caches the source length used by Tree-sitter and TextKit ranges.
    private var textUTF16Length: Int

    /// Holds the monotonically increasing document revision.
    private var revision: UInt64

    /// Caches ordered captures for the current document revision.
    ///
    /// A missing value records that a previous query failed after Tree-sitter
    /// had already accepted an edit. The next snapshot request retries a full
    /// query instead of exposing stale highlighting state.
    private var cachedHighlights: [HighlightSpan]?

    /// Creates a session after resolving and parsing its initial source.
    ///
    /// - Parameters:
    ///   - highlighter: The immutable highlighter creating the session.
    ///   - text: The initial source text.
    ///   - language: The canonical identifier or alias of the root language.
    /// - Throws: ``HighlighterError`` when the language or initial parse is
    ///   unavailable.
    init(
        highlighter: Highlighter,
        text: String,
        language: LanguageID
    ) throws(HighlighterError) {
        let textUTF16Length = try highlighter.validateDocumentLength(text)
        let languageDefinition = try highlighter.languageDefinition(
            for: language
        )
        let layer = try highlighter.makeLanguageLayer(
            for: languageDefinition
        )
        layer.replaceContent(with: text)
        let snapshot = try highlighter.makeSnapshot(
            text: text,
            language: languageDefinition.id,
            revision: 0,
            layer: layer,
            documentLength: textUTF16Length
        )

        self.highlighter = highlighter
        self.languageDefinition = languageDefinition
        self.language = languageDefinition.id
        self.layer = layer
        self.text = text
        self.textUTF16Length = textUTF16Length
        self.revision = 0
        self.cachedHighlights = snapshot.highlights
    }

    /// Returns the source text in the current revision.
    public var currentText: String {
        text
    }

    /// Returns the current document revision.
    public var currentRevision: UInt64 {
        revision
    }

    /// Returns the complete highlighting state of the current revision.
    ///
    /// - Returns: An immutable snapshot of the session state.
    /// - Throws: ``HighlighterError`` when query execution fails.
    public func snapshot() throws(HighlighterError) -> HighlightSnapshot {
        if let cachedHighlights {
            return HighlightSnapshot(
                parserProducedText: text,
                language: languageDefinition.id,
                revision: revision,
                highlights: cachedHighlights,
                utf16Length: textUTF16Length
            )
        }

        let snapshot = try highlighter.makeSnapshot(
            text: text,
            language: languageDefinition.id,
            revision: revision,
            layer: layer,
            documentLength: textUTF16Length
        )
        cachedHighlights = snapshot.highlights
        return snapshot
    }

    /// Replaces a UTF-16 range and incrementally reparses the document.
    ///
    /// The returned snapshot is complete, while `invalidatedRanges` identifies
    /// the regions a renderer needs to reconsider. The session retains captures
    /// outside those regions and only queries Tree-sitter for changed syntax.
    ///
    /// - Parameters:
    ///   - range: The range in the current document revision.
    ///   - replacement: The source text that replaces `range`.
    /// - Returns: The new snapshot and Tree-sitter invalidation ranges.
    /// - Throws: ``HighlighterError`` when the range is invalid or highlighting
    ///   the updated document fails.
    @discardableResult
    public func replaceCharacters(
        in range: UTF16Range,
        with replacement: String
    ) throws(HighlighterError) -> HighlightUpdate {
        let oldLength = textUTF16Length
        guard range.upperBound <= oldLength else {
            throw HighlighterError.rangeOutOfBounds(
                range: range,
                textLength: oldLength
            )
        }
        guard let stringRange = Self.stringRange(for: range, in: text) else {
            throw HighlighterError.invalidUTF16Boundary(range)
        }

        let editPoints = Self.points(
            atUTF16Offsets: range.location,
            and: range.upperBound,
            in: text
        )

        let replacementLength = replacement.utf16.count
        let retainedLength = oldLength - range.length
        let (newLength, lengthOverflowed) = retainedLength.addingReportingOverflow(
            replacementLength
        )
        guard !lengthOverflowed else {
            throw HighlighterError.documentTooLarge
        }
        let updatedTextUTF16Length = try highlighter.validateDocumentLength(
            newLength
        )

        var updatedText = text
        updatedText.replaceSubrange(stringRange, with: replacement)

        let replacementRange = UTF16Range(
            location: range.location,
            length: replacementLength
        )
        let newEndPoint = Self.endPoint(
            of: replacement,
            startingAt: editPoints.start
        )
        let edit = InputEdit(
            startByte: UInt32(range.location * 2),
            oldEndByte: UInt32(range.upperBound * 2),
            newEndByte: UInt32(replacementRange.upperBound * 2),
            startPoint: editPoints.start,
            oldEndPoint: editPoints.end,
            newEndPoint: newEndPoint
        )
        let invalidated = layer.didChangeContent(
            .init(string: updatedText),
            using: edit,
            resolveSublayers: true
        )

        text = updatedText
        textUTF16Length = updatedTextUTF16Length
        revision += 1

        let invalidatedRanges = Self.ranges(
            from: invalidated,
            documentLength: updatedTextUTF16Length
        )

        do {
            if let previousHighlights = cachedHighlights {
                cachedHighlights = try refreshedHighlights(
                    previousHighlights,
                    replacing: range,
                    with: replacementRange,
                    invalidatedRanges: invalidatedRanges
                )
            } else {
                cachedHighlights = nil
            }

            let snapshot = try snapshot()
            return HighlightUpdate(
                replacedRange: range,
                replacementRange: replacementRange,
                invalidatedRanges: invalidatedRanges,
                snapshot: snapshot
            )
        } catch {
            cachedHighlights = nil
            throw error
        }
    }

    /// Refreshes cached captures within the syntax region changed by an edit.
    ///
    /// Captures outside the changed region are shifted by the edit delta and
    /// retained. Captures intersecting that region are replaced by a bounded
    /// Tree-sitter query, which avoids querying an otherwise unchanged file.
    ///
    /// - Parameters:
    ///   - previousHighlights: The ordered captures before the edit.
    ///   - replacedRange: The range removed from the previous revision.
    ///   - replacementRange: The inserted range in the current revision.
    ///   - invalidatedRanges: The regions changed by Tree-sitter.
    /// - Returns: Complete ordered captures for the current revision.
    /// - Throws: ``HighlighterError`` when the bounded query fails.
    private func refreshedHighlights(
        _ previousHighlights: [HighlightSpan],
        replacing replacedRange: UTF16Range,
        with replacementRange: UTF16Range,
        invalidatedRanges: [UTF16Range]
    ) throws(HighlighterError) -> [HighlightSpan] {
        guard
            let refreshRange = Self.refreshRange(
                invalidatedRanges: invalidatedRanges,
                replacementRange: replacementRange,
                documentLength: textUTF16Length
            )
        else {
            return []
        }

        let refreshed = try highlighter.makeHighlights(
            text: text,
            language: languageDefinition.id,
            layer: layer,
            in: NSRange(
                location: refreshRange.location,
                length: refreshRange.length
            ),
            documentLength: textUTF16Length
        )
        let refreshedRanges = Set(refreshed.map(\.range))
        let offsetDelta = replacementRange.length - replacedRange.length
        var retained: [HighlightSpan] = []
        retained.reserveCapacity(previousHighlights.count)

        for highlight in previousHighlights {
            guard
                let rebased = Self.rebased(
                    highlight,
                    around: replacedRange,
                    offsetDelta: offsetDelta
                ),
                !rebased.range.overlaps(refreshRange),
                !refreshedRanges.contains(rebased.range)
            else {
                continue
            }
            retained.append(rebased)
        }

        return Self.merge(retained, with: refreshed)
    }

    /// Rebases one capture around an edited range.
    ///
    /// Captures intersecting the edit are discarded because the bounded query
    /// replaces them. Captures after the edit move by the UTF-16 length delta.
    ///
    /// - Parameters:
    ///   - highlight: The capture from the previous revision.
    ///   - replacedRange: The range removed from the previous revision.
    ///   - offsetDelta: The replacement length minus the removed length.
    /// - Returns: The unchanged or shifted capture, or `nil` when it intersects
    ///   the edit.
    private static func rebased(
        _ highlight: HighlightSpan,
        around replacedRange: UTF16Range,
        offsetDelta: Int
    ) -> HighlightSpan? {
        if highlight.range.upperBound <= replacedRange.location {
            return highlight
        }
        if highlight.range.location >= replacedRange.upperBound {
            return HighlightSpan(
                scopeComponents: highlight.scopeComponents,
                range: UTF16Range(
                    location: highlight.range.location + offsetDelta,
                    length: highlight.range.length
                )
            )
        }
        return nil
    }

    /// Returns one bounded query region for all invalidated syntax.
    ///
    /// The region includes adjacent UTF-16 units when available. This lets the
    /// bounded query replace captures that grow or merge across either edit
    /// boundary, including insertions at the end of an existing capture.
    ///
    /// - Parameters:
    ///   - invalidatedRanges: The regions changed by Tree-sitter.
    ///   - replacementRange: The inserted range in the current revision.
    ///   - documentLength: The current UTF-16 document length.
    /// - Returns: A nonempty bounded range, or `nil` for an empty document.
    private static func refreshRange(
        invalidatedRanges: [UTF16Range],
        replacementRange: UTF16Range,
        documentLength: Int
    ) -> UTF16Range? {
        guard documentLength > 0 else {
            return nil
        }

        var lowerBound = min(replacementRange.location, documentLength)
        var upperBound = min(replacementRange.upperBound, documentLength)

        for range in invalidatedRanges {
            lowerBound = min(lowerBound, range.location)
            upperBound = max(upperBound, range.upperBound)
        }

        if lowerBound > 0 {
            lowerBound -= 1
        }
        if upperBound < documentLength {
            upperBound += 1
        }

        return UTF16Range(lowerBound..<upperBound)
    }

    /// Merges two ordered capture arrays without sorting the complete result.
    ///
    /// - Parameters:
    ///   - retained: The ordered captures preserved from the previous revision.
    ///   - refreshed: The ordered captures returned by the bounded query.
    /// - Returns: Every capture in deterministic application order.
    private static func merge(
        _ retained: [HighlightSpan],
        with refreshed: [HighlightSpan]
    ) -> [HighlightSpan] {
        var result: [HighlightSpan] = []
        result.reserveCapacity(retained.count + refreshed.count)
        var retainedIndex = retained.startIndex
        var refreshedIndex = refreshed.startIndex

        while retainedIndex < retained.endIndex,
            refreshedIndex < refreshed.endIndex
        {
            if refreshed[refreshedIndex] < retained[retainedIndex] {
                result.append(refreshed[refreshedIndex])
                refreshedIndex += 1
            } else {
                result.append(retained[retainedIndex])
                retainedIndex += 1
            }
        }

        result.append(contentsOf: retained[retainedIndex...])
        result.append(contentsOf: refreshed[refreshedIndex...])
        return result
    }

    /// Computes two Tree-sitter points during one traversal of the source.
    ///
    /// Document-length validation guarantees both values fit in `UInt32`.
    ///
    /// - Parameters:
    ///   - startOffset: The first UTF-16 offset to locate.
    ///   - endOffset: The second UTF-16 offset to locate.
    ///   - text: The complete source text.
    /// - Returns: The corresponding zero-based Tree-sitter points.
    private static func points(
        atUTF16Offsets startOffset: Int,
        and endOffset: Int,
        in text: String
    ) -> (start: Point, end: Point) {
        var row: UInt32 = 0
        var column: UInt32 = 0
        var currentOffset = 0
        var startPoint = startOffset == 0 ? Point.zero : nil

        for codeUnit in text.utf16.prefix(endOffset) {
            if codeUnit == 0x0A {
                row += 1
                column = 0
            } else {
                column += 2
            }
            currentOffset += 1
            if currentOffset == startOffset {
                startPoint = Point(row: row, column: column)
            }
        }

        let endPoint = Point(row: row, column: column)
        return (startPoint ?? endPoint, endPoint)
    }

    /// Advances a Tree-sitter point across newly inserted UTF-16 text.
    ///
    /// Document-length validation guarantees the result fits in `UInt32`.
    ///
    /// - Parameters:
    ///   - replacement: The source text inserted at the starting point.
    ///   - startPoint: The point immediately before the replacement.
    /// - Returns: The point immediately after the replacement.
    private static func endPoint(
        of replacement: String,
        startingAt startPoint: Point
    ) -> Point {
        var row = startPoint.row
        var column = startPoint.column

        for codeUnit in replacement.utf16 {
            if codeUnit == 0x0A {
                row += 1
                column = 0
            } else {
                column += 2
            }
        }
        return Point(row: row, column: column)
    }

    /// Converts a typed UTF-16 range without rounding split Unicode scalars.
    ///
    /// - Parameters:
    ///   - range: The UTF-16 range to convert.
    ///   - text: The source string that owns the indices.
    /// - Returns: A valid Swift range, or `nil` when either boundary lies
    ///   inside a Unicode scalar.
    private static func stringRange(
        for range: UTF16Range,
        in text: String
    ) -> Range<String.Index>? {
        let utf16 = text.utf16
        let lowerUTF16 = utf16.index(
            utf16.startIndex,
            offsetBy: range.location
        )
        let upperUTF16 = utf16.index(
            lowerUTF16,
            offsetBy: range.length
        )
        guard
            let lowerBound = String.Index(lowerUTF16, within: text),
            let upperBound = String.Index(upperUTF16, within: text)
        else {
            return nil
        }
        return lowerBound..<upperBound
    }

    /// Converts an index set into sorted, bounded public ranges.
    ///
    /// - Parameters:
    ///   - indexSet: The offsets invalidated by SwiftTreeSitterLayer.
    ///   - documentLength: The UTF-16 length of the updated document.
    /// - Returns: Nonempty invalidation ranges bounded to the new document.
    private static func ranges(
        from indexSet: IndexSet,
        documentLength: Int
    ) -> [UTF16Range] {
        indexSet.rangeView.compactMap { range in
            let lowerBound = min(max(0, range.lowerBound), documentLength)
            let upperBound = min(max(lowerBound, range.upperBound), documentLength)
            guard lowerBound < upperBound else {
                return nil
            }
            return UTF16Range(lowerBound..<upperBound)
        }
    }
}
