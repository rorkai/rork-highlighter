/// Identifies one kind of Tree-sitter query associated with a language.
public enum LanguageQueryKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// Selects syntax captures that become highlight spans.
    case highlights

    /// Selects embedded source ranges and names their nested languages.
    case injections

    /// Selects local definitions, references, and scopes used by richer queries.
    case locals
}
