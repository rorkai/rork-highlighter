/// Shares UTF-16 boundary validation across native rendering adapters.
extension HighlightSnapshot {
    /// Validates every highlight range without retaining converted indices.
    ///
    /// The TextKit renderer already consumes UTF-16 offsets through `NSRange`,
    /// so this path avoids allocating an index dictionary that it cannot use.
    ///
    /// - Throws: ``HighlightRenderingError`` when a range is outside the text
    ///   or does not align with Swift character boundaries.
    func validateHighlightRanges() throws(HighlightRenderingError) {
        guard !hasParserProducedHighlightRanges else {
            return
        }

        let offsets = try highlightBoundaryOffsets()
        let utf16 = text.utf16
        var utf16Index = utf16.startIndex
        var previousOffset = 0
        var invalidOffsets: Set<Int> = []

        for offset in offsets {
            utf16Index = utf16.index(
                utf16Index,
                offsetBy: offset - previousOffset
            )
            previousOffset = offset

            if String.Index(utf16Index, within: text) == nil {
                invalidOffsets.insert(offset)
            }
        }

        for highlight in highlights
        where invalidOffsets.contains(highlight.range.location)
            || invalidOffsets.contains(highlight.range.upperBound)
        {
            throw HighlightRenderingError.invalidUTF16Boundary(
                highlight.range
            )
        }
    }

    /// Resolves every requested UTF-16 boundary to an index in ``text``.
    ///
    /// Offsets advance monotonically through the UTF-16 view so documents with
    /// many captures do not require one complete source scan per range.
    ///
    /// - Returns: Valid text indices keyed by their UTF-16 offsets.
    /// - Throws: ``HighlightRenderingError`` when a range is outside the text
    ///   or does not align with Swift character boundaries.
    func validatedTextIndicesForHighlights()
        throws(HighlightRenderingError) -> [Int: String.Index]
    {
        let offsets = try highlightBoundaryOffsets()
        let utf16 = text.utf16
        var utf16Index = utf16.startIndex
        var previousOffset = 0
        var indices: [Int: String.Index] = [:]
        indices.reserveCapacity(offsets.count)

        for offset in offsets {
            utf16Index = utf16.index(
                utf16Index,
                offsetBy: offset - previousOffset
            )
            previousOffset = offset

            if let textIndex = String.Index(utf16Index, within: text) {
                indices[offset] = textIndex
            }
        }

        for highlight in highlights {
            guard
                indices[highlight.range.location] != nil,
                indices[highlight.range.upperBound] != nil
            else {
                throw HighlightRenderingError.invalidUTF16Boundary(
                    highlight.range
                )
            }
        }

        return indices
    }

    /// Collects unique highlight boundaries after checking document bounds.
    ///
    /// - Returns: UTF-16 boundary offsets sorted in ascending order.
    /// - Throws: ``HighlightRenderingError`` when a highlight extends beyond
    ///   ``text``.
    private func highlightBoundaryOffsets()
        throws(HighlightRenderingError) -> [Int]
    {
        let textLength = text.utf16.count
        var offsets: Set<Int> = []
        offsets.reserveCapacity(highlights.count)

        for highlight in highlights {
            guard highlight.range.upperBound <= textLength else {
                throw HighlightRenderingError.rangeOutOfBounds(
                    range: highlight.range,
                    textLength: textLength
                )
            }
            offsets.insert(highlight.range.location)
            offsets.insert(highlight.range.upperBound)
        }

        return offsets.sorted()
    }
}
