import Foundation

/// Describes a source range that cannot be rendered safely.
public enum HighlightRenderingError: Error, Equatable, Sendable {
    /// A highlight range extends beyond the snapshot text.
    case rangeOutOfBounds(range: UTF16Range, textLength: Int)

    /// A highlight range does not align with Swift character boundaries.
    case invalidUTF16Boundary(UTF16Range)
}

/// Supplies readable descriptions while preserving structured rendering
/// failures.
extension HighlightRenderingError: LocalizedError {
    /// Provides a stable explanation suitable for logs and user interfaces.
    public var errorDescription: String? {
        switch self {
        case .rangeOutOfBounds(let range, let textLength):
            "The UTF-16 range \(range) exceeds the snapshot length of \(textLength)."
        case .invalidUTF16Boundary(let range):
            "The UTF-16 range \(range) does not align with Swift character boundaries."
        }
    }
}
