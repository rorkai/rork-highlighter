#if (canImport(UIKit) && !os(watchOS)) || canImport(AppKit)
    import Foundation

    /// Describes snapshot or storage state that prevents TextKit rendering.
    public enum TextKitRenderingError: Error, Equatable, Sendable {
        /// The snapshot contains a highlight range that cannot be rendered.
        case invalidSnapshot(HighlightRenderingError)

        /// TextKit storage does not contain the snapshot source being rendered.
        case textStorageMismatch(
            snapshotRevision: UInt64,
            expectedLength: Int,
            actualLength: Int
        )
    }

    /// Supplies readable descriptions while preserving structured TextKit
    /// failures.
    extension TextKitRenderingError: LocalizedError {
        /// Provides a stable explanation suitable for logs and user interfaces.
        public var errorDescription: String? {
            switch self {
            case .invalidSnapshot(let error):
                error.errorDescription
            case .textStorageMismatch(
                let snapshotRevision,
                let expectedLength,
                let actualLength
            ):
                "Text storage does not contain snapshot revision \(snapshotRevision). "
                    + "The snapshot has \(expectedLength) UTF-16 code units and the storage has \(actualLength)."
            }
        }
    }
#endif
