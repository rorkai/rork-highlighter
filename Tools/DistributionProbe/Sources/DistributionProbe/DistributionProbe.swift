import RorkHighlighter

/// Links and exercises the complete bundled language catalog.
@main
private enum DistributionProbe {
    /// Highlights Swift so the release binary retains the complete catalog.
    ///
    /// - Throws: ``HighlighterError`` when the bundled catalog is invalid.
    static func main() throws {
        let highlighter = try Highlighter()
        let snapshot = try highlighter.highlight(
            "let answer = 42",
            as: .swift
        )
        print(snapshot.highlights.count)
    }
}
