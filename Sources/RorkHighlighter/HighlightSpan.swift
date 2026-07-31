/// Associates a Tree-sitter capture scope with a UTF-16 source range.
///
/// Highlight spans may overlap. When scopes overlap, clients should apply
/// later and more specific spans after earlier spans.
public struct HighlightSpan: Hashable, Sendable, Codable, Comparable {
    /// Holds the capture components from least specific to most specific.
    public let scopeComponents: [String]

    /// Holds the source range covered by the capture.
    public let range: UTF16Range

    /// Creates a highlight span from a dotted capture scope.
    ///
    /// - Parameters:
    ///   - scope: The Tree-sitter capture name such as `string.special.key`.
    ///   - range: The UTF-16 source range covered by the capture.
    public init(scope: String, range: UTF16Range) {
        self.init(
            scopeComponents: scope.split(separator: ".").map(String.init),
            range: range
        )
    }

    /// Creates a highlight span from individual capture components.
    ///
    /// - Parameters:
    ///   - scopeComponents: Capture components ordered from broad to specific.
    ///   - range: The UTF-16 source range covered by the capture.
    public init(scopeComponents: [String], range: UTF16Range) {
        self.scopeComponents = scopeComponents
        self.range = range
    }

    /// Returns the dotted capture name used by Tree-sitter themes.
    public var scope: String {
        scopeComponents.joined(separator: ".")
    }

    /// Orders spans by range and then by capture specificity.
    ///
    /// - Parameters:
    ///   - lhs: The span on the left side of the comparison.
    ///   - rhs: The span on the right side of the comparison.
    /// - Returns: `true` when `lhs` should be applied before `rhs`.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.range != rhs.range {
            return lhs.range < rhs.range
        }
        if lhs.scopeComponents.count != rhs.scopeComponents.count {
            return lhs.scopeComponents.count < rhs.scopeComponents.count
        }
        return lhs.scopeComponents.lexicographicallyPrecedes(
            rhs.scopeComponents
        )
    }
}
