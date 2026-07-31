/// Captures the complete highlighting state of one document revision.
public struct HighlightSnapshot: Hashable, Sendable {
    /// Holds the source text represented by the snapshot.
    public let text: String

    /// Identifies the root language used to parse the text.
    public let language: LanguageID

    /// Identifies the document revision represented by the snapshot.
    public let revision: UInt64

    /// Holds every highlight span in deterministic application order.
    public let highlights: [HighlightSpan]

    /// Creates an immutable highlighting snapshot.
    ///
    /// - Parameters:
    ///   - text: The source text represented by the snapshot.
    ///   - language: The root language used to parse the text.
    ///   - revision: The document revision represented by the snapshot.
    ///   - highlights: The highlight spans in deterministic application order.
    public init(
        text: String,
        language: LanguageID,
        revision: UInt64,
        highlights: [HighlightSpan]
    ) {
        self.text = text
        self.language = language
        self.revision = revision
        self.highlights = highlights
    }
}
