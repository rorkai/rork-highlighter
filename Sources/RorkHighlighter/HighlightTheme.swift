/// Resolves Tree-sitter capture scopes into renderer-neutral styles.
///
/// Matching is case-sensitive and proceeds from broad scopes to specific
/// scopes. Resolving `string.special.key` applies rules for `string`,
/// `string.special`, and `string.special.key` in that order.
public struct HighlightTheme: Hashable, Sendable, Codable {
    /// Holds the human-readable theme name.
    public let name: String

    /// Holds the style applied before scope-specific refinements.
    public let baseStyle: HighlightStyle

    /// Maps dotted Tree-sitter capture scopes to style refinements.
    public let styles: [String: HighlightStyle]

    /// Creates an immutable highlight theme.
    ///
    /// - Parameters:
    ///   - name: The human-readable theme name.
    ///   - baseStyle: The style applied before scope-specific refinements.
    ///   - styles: The style refinements keyed by dotted capture scope.
    public init(
        name: String,
        baseStyle: HighlightStyle = HighlightStyle(),
        styles: [String: HighlightStyle] = [:]
    ) {
        self.name = name
        self.baseStyle = baseStyle
        self.styles = styles
    }

    /// Resolves a dotted Tree-sitter capture scope.
    ///
    /// Invalid or unknown scopes receive ``baseStyle``.
    ///
    /// - Parameter scope: The dotted capture scope to resolve.
    /// - Returns: The style produced by hierarchical rule refinement.
    public func style(for scope: String) -> HighlightStyle {
        let components = scope.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard components.allSatisfy({ !$0.isEmpty }) else {
            return baseStyle
        }
        return resolvedStyle(
            for: components.map(String.init)
        )
    }

    /// Resolves the capture scope carried by a highlight span.
    ///
    /// - Parameter span: The highlighted source span to resolve.
    /// - Returns: The style produced by hierarchical rule refinement.
    public func style(for span: HighlightSpan) -> HighlightStyle {
        resolvedStyle(for: span.scopeComponents)
    }

    /// Applies matching rules from the broadest component to the most
    /// specific component.
    ///
    /// - Parameter components: The capture components ordered by specificity.
    /// - Returns: The fully resolved style.
    private func resolvedStyle(
        for components: [String]
    ) -> HighlightStyle {
        guard components.allSatisfy({ !$0.isEmpty }) else {
            return baseStyle
        }

        var resolvedStyle = baseStyle
        var candidateScope = ""

        for component in components {
            if !candidateScope.isEmpty {
                candidateScope.append(".")
            }
            candidateScope.append(component)

            if let refinement = styles[candidateScope] {
                resolvedStyle = resolvedStyle.merging(refinement)
            }
        }

        return resolvedStyle
    }
}
