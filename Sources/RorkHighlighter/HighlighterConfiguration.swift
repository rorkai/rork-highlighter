/// Configures behavior shared by one-shot and incremental highlighting.
public struct HighlighterConfiguration: Hashable, Sendable, Codable {
    /// Names the fields in the stable serialized representation.
    private enum CodingKeys: String, CodingKey {
        /// Identifies the maximum nested language depth.
        case maximumInjectionDepth
    }

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

    /// Decodes a configuration after validating its public invariants.
    ///
    /// - Parameter decoder: The decoder containing the serialized
    ///   configuration.
    /// - Throws: `DecodingError` when the injection depth is negative.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let maximumInjectionDepth = try container.decode(
            Int.self,
            forKey: .maximumInjectionDepth
        )
        guard maximumInjectionDepth >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .maximumInjectionDepth,
                in: container,
                debugDescription:
                    "Maximum injection depth cannot be negative."
            )
        }
        self.maximumInjectionDepth = maximumInjectionDepth
    }

    /// Provides the recommended configuration for general source files.
    public static let `default` = Self()
}
