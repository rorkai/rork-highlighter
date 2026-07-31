import HighlightKit

/// Isolates HighlightKit names that otherwise collide with Rork Highlighter.
final class HighlightKitAdapter: Sendable {
    /// Reuses one highlighter configured with only the shared Swift grammar.
    private let highlighter: HighlightKit.Highlighter

    /// Creates a highlighter without loading unrelated language definitions.
    init() {
        highlighter = HighlightKit.Highlighter(
            languages: [LanguageCatalog.swift]
        )
    }

    /// Produces HighlightKit's public flat token collection.
    ///
    /// - Parameter source: The source document to highlight.
    /// - Returns: The number of tokens in the public result.
    func tokenCount(_ source: String) -> Int {
        highlighter.highlight(source, as: "swift").tokens.count
    }

    /// Produces HighlightKit's complete native attributed output.
    ///
    /// - Parameter source: The source document to highlight and render.
    /// - Returns: The UTF-16 length of the rendered attributed string.
    func attributedStringLength(_ source: String) -> Int {
        highlighter.attributedString(
            for: source,
            language: "swift",
            theme: .xcode
        ).length
    }
}
