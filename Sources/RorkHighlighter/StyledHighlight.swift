/// Pairs a semantic highlight span with its resolved visual style.
///
/// Styled highlights preserve the order of their source snapshot and may
/// overlap. Rendering backends should apply later values after earlier values
/// when they need the same refinement behavior as the original captures.
public struct StyledHighlight: Hashable, Sendable, Codable {
    /// Holds the semantic capture and source range produced by Tree-sitter.
    public let span: HighlightSpan

    /// Holds the renderer-neutral style resolved by a theme.
    public let style: HighlightStyle

    /// Creates a styled highlight from a semantic span and resolved style.
    ///
    /// - Parameters:
    ///   - span: The semantic capture and source range to preserve.
    ///   - style: The resolved visual style for the capture.
    public init(span: HighlightSpan, style: HighlightStyle) {
        self.span = span
        self.style = style
    }

    /// Returns the UTF-16 source range covered by the semantic span.
    public var range: UTF16Range {
        span.range
    }
}
