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

    /// Holds the UTF-16 length of the leading source whose parse is settled.
    ///
    /// Streamed documents usually end inside an unfinished token or
    /// construct, and Tree-sitter classifies that tail through error
    /// recovery. Highlights that end before this boundary match a one-shot
    /// highlight of the same text and rarely change when more source is
    /// appended, while highlights at or beyond it remain speculative.
    /// Parser-produced snapshots always carry a value. The value is `nil`
    /// when a snapshot was assembled by hand without parse information, and
    /// it stays out of snapshot equality like other derived parse metadata.
    public let stableUTF16Length: Int?

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
    ///   - stableUTF16Length: The length of the leading source whose parse is
    ///     settled, or `nil` when that boundary is unknown.
    public init(
        text: String,
        language: LanguageID,
        revision: UInt64,
        highlights: [HighlightSpan],
        stableUTF16Length: Int? = nil
    ) {
        let utf16Length = text.utf16.count
        self.init(
            text: text,
            language: language,
            revision: revision,
            highlights: highlights,
            stableUTF16Length: stableUTF16Length.map {
                Self.scalarAlignedBoundary(
                    $0,
                    in: text,
                    utf16Length: utf16Length
                )
            },
            utf16Length: utf16Length,
            hasParserProducedHighlightRanges: false
        )
    }

    /// Clamps a caller-supplied boundary to the text and its scalars.
    ///
    /// Parser-produced boundaries always land between tokens, but hand-built
    /// snapshots can carry any number, and a boundary inside a surrogate
    /// pair would let clients build invalid UTF-16 ranges. The boundary
    /// rounds down to the nearest Unicode scalar boundary.
    ///
    /// - Parameters:
    ///   - value: The caller-supplied boundary.
    ///   - text: The snapshot source text.
    ///   - utf16Length: The UTF-16 length of the source text.
    /// - Returns: A boundary inside the text on a scalar boundary.
    private static func scalarAlignedBoundary(
        _ value: Int,
        in text: String,
        utf16Length: Int
    ) -> Int {
        let clamped = min(max(value, 0), utf16Length)
        guard clamped > 0, clamped < utf16Length else {
            return clamped
        }

        let utf16 = text.utf16
        let candidate = utf16.index(
            utf16.startIndex,
            offsetBy: clamped
        )
        guard String.Index(candidate, within: text) == nil else {
            return clamped
        }
        return clamped - 1
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
    ///   - stableUTF16Length: The settled prefix length derived from the
    ///     parsed syntax trees.
    ///   - utf16Length: The validated UTF-16 length of the parsed source.
    init(
        parserProducedText text: String,
        language: LanguageID,
        revision: UInt64,
        highlights: [HighlightSpan],
        stableUTF16Length: Int,
        utf16Length: Int
    ) {
        self.init(
            text: text,
            language: language,
            revision: revision,
            highlights: highlights,
            stableUTF16Length: stableUTF16Length,
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
    ///   - stableUTF16Length: The settled prefix length, or `nil` when that
    ///     boundary is unknown.
    ///   - utf16Length: The UTF-16 length of the source text.
    ///   - hasParserProducedHighlightRanges: Whether parsing produced the
    ///     capture ranges.
    private init(
        text: String,
        language: LanguageID,
        revision: UInt64,
        highlights: [HighlightSpan],
        stableUTF16Length: Int?,
        utf16Length: Int,
        hasParserProducedHighlightRanges: Bool
    ) {
        self.text = text
        self.language = language
        self.revision = revision
        self.highlights = highlights
        self.stableUTF16Length = stableUTF16Length
        self.utf16Length = utf16Length
        self.hasParserProducedHighlightRanges =
            hasParserProducedHighlightRanges
    }

    /// Compares the observable highlighting state of two snapshots.
    ///
    /// Range provenance and the derived stability boundary affect rendering
    /// work but not the snapshot value that callers observe.
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
