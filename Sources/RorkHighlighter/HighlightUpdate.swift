/// Describes the highlighting state produced by an incremental text edit.
public struct HighlightUpdate: Hashable, Sendable {
    /// Holds the range replaced in the previous document revision.
    public let replacedRange: UTF16Range

    /// Holds the replacement range in the new document revision.
    public let replacementRange: UTF16Range

    /// Holds ranges whose syntax or highlights may have changed.
    public let invalidatedRanges: [UTF16Range]

    /// Holds the complete highlighting state after the edit.
    public let snapshot: HighlightSnapshot

    /// Creates an incremental highlighting update.
    ///
    /// - Parameters:
    ///   - replacedRange: The range removed from the previous revision.
    ///   - replacementRange: The replacement range in the new revision.
    ///   - invalidatedRanges: The ranges requiring display invalidation.
    ///   - snapshot: The complete state after the edit.
    public init(
        replacedRange: UTF16Range,
        replacementRange: UTF16Range,
        invalidatedRanges: [UTF16Range],
        snapshot: HighlightSnapshot
    ) {
        self.replacedRange = replacedRange
        self.replacementRange = replacementRange
        self.invalidatedRanges = invalidatedRanges
        self.snapshot = snapshot
    }
}
