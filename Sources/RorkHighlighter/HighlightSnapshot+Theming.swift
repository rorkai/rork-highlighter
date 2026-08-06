/// Adds framework-agnostic theme resolution to highlight snapshots.
public extension HighlightSnapshot {
    /// Returns the snapshot highlights with styles resolved by a theme.
    ///
    /// The returned values preserve the snapshot's capture order and may
    /// overlap. Rendering backends should apply later values after earlier
    /// values when specific captures refine broader captures.
    ///
    /// - Parameter theme: The theme used to resolve each capture scope.
    /// - Returns: The ordered semantic spans and their resolved styles.
    func styledHighlights(
        using theme: HighlightTheme
    ) -> [StyledHighlight] {
        var styleCache = HighlightStyleCache(theme: theme)
        return highlights.map { span in
            StyledHighlight(
                span: span,
                style: styleCache.style(for: span)
            )
        }
    }
}
