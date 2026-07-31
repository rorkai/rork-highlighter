/// Describes renderer-neutral visual attributes for highlighted text.
///
/// Optional values support hierarchical theme inheritance. A missing value
/// preserves the broader style, while an empty ``textTraits`` set explicitly
/// removes traits inherited from broader theme rules.
public struct HighlightStyle: Hashable, Sendable, Codable {
    /// Holds the foreground color supplied by this style.
    public let foregroundColor: HighlightColor?

    /// Holds the background color supplied by this style.
    public let backgroundColor: HighlightColor?

    /// Holds the text traits supplied by this style.
    public let textTraits: Set<HighlightTextTrait>?

    /// Creates a renderer-neutral highlight style.
    ///
    /// - Parameters:
    ///   - foregroundColor: The foreground color supplied by the style.
    ///   - backgroundColor: The background color supplied by the style.
    ///   - textTraits: The text traits supplied by the style.
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
