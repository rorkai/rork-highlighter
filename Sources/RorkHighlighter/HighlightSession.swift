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

    /// Holds the monotonically increasing document revision.
    private var revision: UInt64

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
    ) throws {
        try highlighter.validateDocumentLength(text)
        let languageDefinition = try highlighter.languageDefinition(
            for: language
        )
        let layer = try highlighter.makeLanguageLayer(
            for: languageDefinition
        )
        layer.replaceContent(with: text)
        _ = try highlighter.makeSnapshot(
            text: text,
            language: languageDefinition.id,
            revision: 0,
            layer: layer
        )

        self.highlighter = highlighter
        self.languageDefinition = languageDefinition
        self.language = languageDefinition.id
        self.layer = layer
        self.text = text
        self.revision = 0
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
    public func snapshot() throws -> HighlightSnapshot {
        try highlighter.makeSnapshot(
            text: text,
            language: languageDefinition.id,
            revision: revision,
            layer: layer
        )
    }

    /// Replaces a UTF-16 range and incrementally reparses the document.
    ///
    /// The returned snapshot is complete, while `invalidatedRanges` identifies
    /// the regions a renderer needs to reconsider. This keeps the first API
    /// correct for simple clients and leaves room for a later token-delta
    /// renderer without changing edit semantics.
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
    ) throws -> HighlightUpdate {
        let oldLength = text.utf16.count
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

        var updatedText = text
        updatedText.replaceSubrange(stringRange, with: replacement)
        try highlighter.validateDocumentLength(updatedText)

        let replacementRange = UTF16Range(
            location: range.location,
            length: replacement.utf16.count
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
        revision += 1

        let snapshot = try snapshot()
        return HighlightUpdate(
            replacedRange: range,
            replacementRange: replacementRange,
            invalidatedRanges: Self.ranges(
                from: invalidated,
                documentLength: updatedText.utf16.count
            ),
            snapshot: snapshot
        )
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
