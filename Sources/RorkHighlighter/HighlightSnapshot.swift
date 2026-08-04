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

    /// Caches the Foundation-native length used by incremental renderers.
    let utf16Length: Int

    /// Records whether every range came from the producing parser.
    ///
    /// Publicly constructed snapshots remain untrusted because their captures
    /// can contain arbitrary offsets. Parser-produced snapshots use this marker
    /// to avoid repeating a complete Unicode boundary scan and retain the
    /// collector's source ordering while rendering.
    let hasParserProducedHighlightRanges: Bool

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
        self.init(
            text: text,
            language: language,
            revision: revision,
            highlights: highlights,
            utf16Length: text.utf16.count,
            hasParserProducedHighlightRanges: false
        )
    }

    /// Creates a parser-produced snapshot whose ranges are already trusted.
    ///
    /// Tree-sitter emits UTF-16 boundaries from the same source text carried by
    /// the snapshot, so native rendering can safely consume those ranges
    /// without validating every boundary again.
    ///
    /// - Parameters:
    ///   - text: The source text represented by the snapshot.
    ///   - language: The root language used to parse the text.
    ///   - revision: The document revision represented by the snapshot.
    ///   - highlights: The ordered captures produced by Tree-sitter.
    ///   - utf16Length: The validated UTF-16 length of the parsed source.
    init(
        parserProducedText text: String,
        language: LanguageID,
        revision: UInt64,
        highlights: [HighlightSpan],
        utf16Length: Int
    ) {
        self.init(
            text: text,
            language: language,
            revision: revision,
            highlights: highlights,
            utf16Length: utf16Length,
            hasParserProducedHighlightRanges: true
        )
    }

    /// Creates a snapshot with explicit range provenance.
    ///
    /// - Parameters:
    ///   - text: The source text represented by the snapshot.
    ///   - language: The root language used to parse the text.
    ///   - revision: The document revision represented by the snapshot.
    ///   - highlights: The ordered captures applied during rendering.
    ///   - utf16Length: The UTF-16 length of the source text.
    ///   - hasParserProducedHighlightRanges: Whether parsing produced the
    ///     capture ranges.
    private init(
        text: String,
        language: LanguageID,
        revision: UInt64,
        highlights: [HighlightSpan],
        utf16Length: Int,
        hasParserProducedHighlightRanges: Bool
    ) {
        self.text = text
        self.language = language
        self.revision = revision
        self.highlights = highlights
        self.utf16Length = utf16Length
        self.hasParserProducedHighlightRanges =
            hasParserProducedHighlightRanges
    }

    /// Compares the observable highlighting state of two snapshots.
    ///
    /// Range provenance affects rendering work but not the snapshot value that
    /// callers observe.
    ///
    /// - Parameters:
    ///   - lhs: The snapshot on the left side of the comparison.
    ///   - rhs: The snapshot on the right side of the comparison.
    /// - Returns: `true` when both snapshots describe the same highlighting.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
            && lhs.language == rhs.language
            && lhs.revision == rhs.revision
            && lhs.highlights == rhs.highlights
    }

    /// Hashes the observable highlighting state of this snapshot.
    ///
    /// - Parameter hasher: The standard library hasher receiving each field.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(language)
        hasher.combine(revision)
        hasher.combine(highlights)
    }
}
