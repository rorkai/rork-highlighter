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

    /// Caches the settled prefix length for the current document revision.
    ///
    /// The value follows the same lifecycle as ``cachedHighlights`` so a
    /// snapshot built from cached captures still reports the stability of
    /// the current syntax tree.
    private var cachedStableUTF16Length: Int?

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
        self.cachedStableUTF16Length = snapshot.stableUTF16Length
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
            let stableUTF16Length =
                cachedStableUTF16Length
                ?? highlighter.stableUTF16Length(
                    of: layer,
                    text: text,
                    documentLength: textUTF16Length
                )
            cachedStableUTF16Length = stableUTF16Length
            return HighlightSnapshot(
                parserProducedText: text,
                language: languageDefinition.id,
                revision: revision,
                highlights: cachedHighlights,
                stableUTF16Length: stableUTF16Length,
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
        cachedStableUTF16Length = snapshot.stableUTF16Length
        return snapshot
    }

    /// Replaces a UTF-16 range and incrementally reparses the document.
    ///
    /// The returned snapshot is complete, while `invalidatedRanges` identifies
    /// every region a renderer needs to reconsider. Parsing reuses the edited
    /// syntax tree, and the query runs over the complete document so the
    /// captures always match a one-shot highlight of the same tree. Bounding
    /// the query to Tree-sitter's changed ranges was tried instead and
    /// dropped, because query patterns can match or stop matching nodes whose
    /// own structure never changed.
    ///
    /// - Parameters:
    ///   - range: The range in the current document revision.
    ///   - replacement: The source text that replaces `range`.
    /// - Returns: The new snapshot and its invalidation ranges.
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
            let previousHighlights = cachedHighlights
            cachedHighlights = nil
            cachedStableUTF16Length = nil

            let snapshot = try snapshot()
            return HighlightUpdate(
                replacedRange: range,
                replacementRange: replacementRange,
                invalidatedRanges: Self.mergedInvalidatedRanges(
                    treeRanges: invalidatedRanges,
                    captureDiffRanges: Self.captureDiffRanges(
                        previous: previousHighlights ?? [],
                        current: snapshot.highlights,
                        replacedRange: range,
                        replacementRange: replacementRange
                    ),
                    documentLength: updatedTextUTF16Length
                ),
                snapshot: snapshot
            )
        } catch {
            cachedHighlights = nil
            cachedStableUTF16Length = nil
            throw error
        }
    }

    /// Returns the regions whose captures differ between two revisions.
    ///
    /// Tree-sitter's changed ranges describe structural edits, but a query
    /// pattern can match or stop matching a node whose own structure never
    /// changed, for example a name that becomes a call once its argument
    /// list appears. Renderers repaint only invalidated regions, so every
    /// capture difference has to surface here or stale styles remain
    /// visible. The walk compares both ordered capture lists after rebasing
    /// the previous revision around the edit.
    ///
    /// - Parameters:
    ///   - previous: The ordered captures before the edit.
    ///   - current: The ordered captures after the edit.
    ///   - replacedRange: The range removed from the previous revision.
    ///   - replacementRange: The inserted range in the current revision.
    /// - Returns: Unsorted regions covering every changed capture.
    private static func captureDiffRanges(
        previous: [HighlightSpan],
        current: [HighlightSpan],
        replacedRange: UTF16Range,
        replacementRange: UTF16Range
    ) -> [UTF16Range] {
        let offsetDelta = replacementRange.length - replacedRange.length
        var changedRanges: [UTF16Range] = []
        var rebased: [HighlightSpan] = []
        rebased.reserveCapacity(previous.count)

        for highlight in previous {
            if highlight.range.upperBound <= replacedRange.location {
                rebased.append(highlight)
            } else if highlight.range.location >= replacedRange.upperBound {
                rebased.append(
                    HighlightSpan(
                        scopeComponents: highlight.scopeComponents,
                        range: UTF16Range(
                            location: highlight.range.location + offsetDelta,
                            length: highlight.range.length
                        )
                    )
                )
            } else {
                // A capture that intersected the edit no longer has one
                // defensible position, so both of its possible remainders
                // count as changed.
                if highlight.range.location < replacedRange.location {
                    changedRanges.append(
                        UTF16Range(
                            highlight.range.location..<replacedRange.location
                        )
                    )
                }
                if highlight.range.upperBound > replacedRange.upperBound {
                    let movedUpperBound =
                        highlight.range.upperBound + offsetDelta
                    changedRanges.append(
                        UTF16Range(
                            replacementRange.upperBound..<movedUpperBound
                        )
                    )
                }
            }
        }

        var previousIndex = rebased.startIndex
        var currentIndex = current.startIndex
        while previousIndex < rebased.endIndex,
            currentIndex < current.endIndex
        {
            let previousSpan = rebased[previousIndex]
            let currentSpan = current[currentIndex]
            if previousSpan == currentSpan {
                previousIndex += 1
                currentIndex += 1
            } else if previousSpan < currentSpan {
                changedRanges.append(previousSpan.range)
                previousIndex += 1
            } else {
                changedRanges.append(currentSpan.range)
                currentIndex += 1
            }
        }
        changedRanges.append(
            contentsOf: rebased[previousIndex...].map(\.range)
        )
        changedRanges.append(
            contentsOf: current[currentIndex...].map(\.range)
        )

        return changedRanges
    }

    /// Merges structural and capture invalidation into disjoint ranges.
    ///
    /// - Parameters:
    ///   - treeRanges: The regions Tree-sitter reports as changed.
    ///   - captureDiffRanges: The regions whose captures changed.
    ///   - documentLength: The UTF-16 length of the updated document.
    /// - Returns: Sorted disjoint nonempty ranges bounded to the document.
    private static func mergedInvalidatedRanges(
        treeRanges: [UTF16Range],
        captureDiffRanges: [UTF16Range],
        documentLength: Int
    ) -> [UTF16Range] {
        let bounded = (treeRanges + captureDiffRanges).compactMap {
            range -> UTF16Range? in
            let lowerBound = min(max(0, range.location), documentLength)
            let upperBound = min(
                max(lowerBound, range.upperBound),
                documentLength
            )
            guard lowerBound < upperBound else {
                return nil
            }
            return UTF16Range(lowerBound..<upperBound)
        }
        let sorted = bounded.sorted()
        guard var currentRange = sorted.first else {
            return []
        }

        var result: [UTF16Range] = []
        result.reserveCapacity(sorted.count)
        for range in sorted.dropFirst() {
            if range.location <= currentRange.upperBound {
                let mergedUpperBound = max(
                    currentRange.upperBound,
                    range.upperBound
                )
                currentRange = UTF16Range(
                    currentRange.location..<mergedUpperBound
                )
            } else {
                result.append(currentRange)
                currentRange = range
            }
        }
        result.append(currentRange)
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
