/// Describes a half-open range measured in UTF-16 code units.
///
/// Foundation text systems and SwiftTreeSitter both use UTF-16 offsets for
/// their Swift-facing ranges. Naming the unit prevents callers from mixing
/// UTF-8 byte offsets with editor positions.
public struct UTF16Range:
    Hashable,
    Sendable,
    Codable,
    Comparable,
    CustomStringConvertible
{
    /// Names the fields in the stable serialized representation.
    private enum CodingKeys: String, CodingKey {
        /// Identifies the first UTF-16 code-unit offset.
        case location

        /// Identifies the number of UTF-16 code units.
        case length
    }

    /// Holds the first UTF-16 code-unit offset in the range.
    public let location: Int

    /// Holds the number of UTF-16 code units in the range.
    public let length: Int

    /// Creates a range from its starting offset and length.
    ///
    /// - Parameters:
    ///   - location: The nonnegative starting UTF-16 offset.
    ///   - length: The nonnegative number of UTF-16 code units.
    public init(location: Int, length: Int) {
        precondition(location >= 0, "UTF-16 locations cannot be negative.")
        precondition(length >= 0, "UTF-16 lengths cannot be negative.")
        precondition(
            location <= Int.max - length,
            "The UTF-16 range exceeds the platform integer width."
        )
        self.location = location
        self.length = length
    }

    /// Creates a typed range from integer UTF-16 offsets.
    ///
    /// - Parameter range: The nonnegative half-open UTF-16 range.
    public init(_ range: Range<Int>) {
        self.init(
            location: range.lowerBound,
            length: range.count
        )
    }

    /// Decodes a range after validating its public invariants.
    ///
    /// - Parameter decoder: The decoder containing the serialized range.
    /// - Throws: `DecodingError` when either value is negative or their sum
    ///   exceeds the platform integer width.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let location = try container.decode(
            Int.self,
            forKey: .location
        )
        let length = try container.decode(
            Int.self,
            forKey: .length
        )

        guard location >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .location,
                in: container,
                debugDescription: "UTF-16 locations cannot be negative."
            )
        }
        guard length >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .length,
                in: container,
                debugDescription: "UTF-16 lengths cannot be negative."
            )
        }
        guard location <= Int.max - length else {
            throw DecodingError.dataCorruptedError(
                forKey: .length,
                in: container,
                debugDescription:
                    "The UTF-16 range exceeds the platform integer width."
            )
        }

        self.location = location
        self.length = length
    }

    /// Returns the first offset outside the range.
    public var upperBound: Int {
        location + length
    }

    /// Returns the equivalent standard library range.
    public var range: Range<Int> {
        location..<upperBound
    }

    /// Returns a concise representation for diagnostics.
    public var description: String {
        "\(location)..<\(upperBound)"
    }

    /// Returns whether this range and another range share any offsets.
    ///
    /// Empty ranges do not overlap.
    ///
    /// - Parameter other: The range to compare.
    /// - Returns: `true` when the two ranges overlap.
    public func overlaps(_ other: Self) -> Bool {
        range.overlaps(other.range)
    }

    /// Orders ranges by location and then by length.
    ///
    /// - Parameters:
    ///   - lhs: The range on the left side of the comparison.
    ///   - rhs: The range on the right side of the comparison.
    /// - Returns: `true` when `lhs` sorts before `rhs`.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.location != rhs.location {
            return lhs.location < rhs.location
        }
        return lhs.length < rhs.length
    }
}
