/// Configures behavior shared by one-shot and incremental highlighting.
public struct HighlighterConfiguration: Hashable, Sendable, Codable {
    /// Limits recursive language injections such as fenced code inside Markdown.
    public let maximumInjectionDepth: Int

    /// Creates a highlighting configuration.
    ///
    /// - Parameter maximumInjectionDepth: The number of nested language layers
    ///   the highlighter may resolve. The value must not be negative.
    public init(maximumInjectionDepth: Int = 4) {
        precondition(
            maximumInjectionDepth >= 0,
            "Maximum injection depth cannot be negative."
        )
        self.maximumInjectionDepth = maximumInjectionDepth
    }

    /// Provides the recommended configuration for general source files.
    public static let `default` = Self()
}
