/// Describes renderer-neutral visual attributes for highlighted text.
///
/// Optional values support hierarchical theme inheritance. A missing value
/// preserves the broader style, while an empty ``textTraits`` set explicitly
/// removes inherited typography.
public struct HighlightStyle: Hashable, Sendable, Codable {
    /// Holds the requested foreground color.
    public let foregroundColor: HighlightColor?

    /// Holds the requested background color.
    public let backgroundColor: HighlightColor?

    /// Holds typography that replaces inherited text traits when present.
    public let textTraits: Set<HighlightTextTrait>?

    /// Creates a renderer-neutral highlight style.
    ///
    /// - Parameters:
    ///   - foregroundColor: The requested foreground color.
    ///   - backgroundColor: The requested background color.
    ///   - textTraits: Typography that replaces inherited text traits.
    public init(
        foregroundColor: HighlightColor? = nil,
        backgroundColor: HighlightColor? = nil,
        textTraits: Set<HighlightTextTrait>? = nil
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.textTraits = textTraits
    }

    /// Returns this style with a more specific style applied over it.
    ///
    /// - Parameter refinement: The style that supplies more specific values.
    /// - Returns: A style containing the resolved visual attributes.
    public func merging(_ refinement: Self) -> Self {
        Self(
            foregroundColor:
                refinement.foregroundColor ?? foregroundColor,
            backgroundColor:
                refinement.backgroundColor ?? backgroundColor,
            textTraits: refinement.textTraits ?? textTraits
        )
    }
}
