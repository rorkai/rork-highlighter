/// Shares UTF-16 boundary validation across native rendering adapters.
extension HighlightSnapshot {
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

        let utf16 = text.utf16
        var utf16Index = utf16.startIndex
        var previousOffset = 0
        var indices: [Int: String.Index] = [:]
        indices.reserveCapacity(offsets.count)

        for offset in offsets.sorted() {
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
}
