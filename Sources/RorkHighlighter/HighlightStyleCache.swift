/// Reuses resolved theme styles while one snapshot is rendered.
///
/// Large source files repeat a small vocabulary of Tree-sitter capture scopes.
/// Keeping those resolved values local to one render avoids rebuilding dotted
/// scope prefixes for every token without adding shared mutable state to
/// ``HighlightTheme``.
struct HighlightStyleCache {
    /// Holds the immutable theme whose rules are being resolved.
    private let theme: HighlightTheme

    /// Stores resolved styles by their capture components.
    private var styles: [[String]: HighlightStyle]

    /// Creates an empty cache for one rendering operation.
    ///
    /// - Parameter theme: The theme used to resolve capture scopes.
    init(theme: HighlightTheme) {
        self.theme = theme
        self.styles = [:]
    }

    /// Resolves a span and remembers its style for repeated scopes.
    ///
    /// - Parameter span: The highlighted span whose scope is requested.
    /// - Returns: The fully resolved renderer-neutral style.
    mutating func style(for span: HighlightSpan) -> HighlightStyle {
        if let style = styles[span.scopeComponents] {
            return style
        }

        let style = theme.style(for: span)
        styles[span.scopeComponents] = style
        return style
    }
}
