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

    /// Returns the new-document ranges that a renderer needs to refresh.
    ///
    /// The result combines the replacement with Tree-sitter's invalidation
    /// ranges. Overlapping and adjacent ranges are merged, empty ranges are
    /// omitted, and the remaining ranges are sorted by location.
    public var rangesRequiringRendering: [UTF16Range] {
        Self.mergedRenderingRanges(
            invalidatedRanges + [replacementRange]
        )
    }

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

    /// Merges overlapping and adjacent nonempty rendering ranges.
    ///
    /// - Parameter ranges: The new-document ranges to merge.
    /// - Returns: Sorted disjoint ranges suitable for incremental rendering.
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
}
