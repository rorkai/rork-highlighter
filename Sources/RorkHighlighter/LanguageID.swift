import Foundation

/// Identifies a programming or markup language throughout the highlighting API.
///
/// Identifiers are case-insensitive. Leading and trailing whitespace is
/// removed so language aliases from file metadata and injection queries resolve
/// consistently.
public struct LanguageID:
    RawRepresentable,
    Hashable,
    Sendable,
    Codable,
    Comparable,
    CustomStringConvertible,
    ExpressibleByStringLiteral
{
    /// Holds the normalized identifier used by catalogs and serialized values.
    public let rawValue: String

    /// Creates an identifier from an arbitrary language name.
    ///
    /// Empty identifiers remain representable so decoding and literal
    /// construction stay nonfailable. ``LanguageCatalog`` rejects them before
    /// they can enter a usable catalog.
    ///
    /// - Parameter rawValue: The language name to normalize.
    public init(rawValue: String) {
        self.rawValue = Self.normalize(rawValue)
    }

    /// Creates an identifier with concise call-site syntax.
    ///
    /// - Parameter value: The language name to normalize.
    public init(_ value: String) {
        self.init(rawValue: value)
    }

    /// Creates an identifier from a string literal.
    ///
    /// - Parameter value: The literal language name.
    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// Decodes an identifier from its normalized string representation.
    ///
    /// - Parameter decoder: The decoder that supplies the string value.
    /// - Throws: The decoder's error when the value is not a string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    /// Encodes the normalized identifier as one string value.
    ///
    /// - Parameter encoder: The encoder that receives the string value.
    /// - Throws: The encoder's error when the value cannot be written.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Returns the normalized identifier for diagnostics and display.
    public var description: String {
        rawValue
    }

    /// Orders identifiers by their normalized string values.
    ///
    /// - Parameters:
    ///   - lhs: The identifier on the left side of the comparison.
    ///   - rhs: The identifier on the right side of the comparison.
    /// - Returns: `true` when `lhs` sorts before `rhs`.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Produces the canonical spelling used for lookups.
    ///
    /// - Parameter value: The untrusted language name.
    /// - Returns: A lowercase identifier without surrounding whitespace.
    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
