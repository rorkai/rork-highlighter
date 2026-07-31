import Foundation
import SwiftTreeSitter

/// Describes one parser and the metadata needed to discover and highlight it.
///
/// A definition compiles its query sources during initialization so malformed
/// parser and query combinations fail before a document is opened.
public struct HighlightLanguage: Identifiable, Sendable {
    /// Holds the canonical identifier used by API calls and serialized state.
    public let id: LanguageID

    /// Holds the human-readable language name used by documentation and tools.
    public let displayName: String

    /// Holds alternate identifiers accepted from callers and injection queries.
    public let aliases: Set<LanguageID>

    /// Holds lowercase file extensions without a leading period.
    public let fileExtensions: Set<String>

    /// Holds lowercase filenames preferred over file-extension lookup.
    public let filenames: Set<String>

    /// Holds the compiled parser and queries used to create language layers.
    let configuration: LanguageConfiguration

    /// Creates a language definition around a compiled Tree-sitter parser.
    ///
    /// The parser pointer must remain valid for the lifetime of the process.
    /// Generated Tree-sitter parsers expose process-lifetime pointers and meet
    /// this requirement. A `nil` pointer produces a structured configuration
    /// error instead of requiring a force unwrap at the call site.
    ///
    /// - Parameters:
    ///   - id: The canonical language identifier.
    ///   - displayName: The human-readable language name.
    ///   - aliases: Alternate names accepted by the language catalog.
    ///   - fileExtensions: File extensions associated with the language.
    ///   - filenames: Exact filenames associated with the language.
    ///   - treeSitterLanguage: The pointer returned by a generated parser.
    ///   - highlightsQuery: The query that produces syntax captures.
    ///   - injectionsQuery: The optional query that locates nested languages.
    ///   - localsQuery: The optional query that describes local scopes.
    /// - Throws: ``HighlighterError`` when the identifier, parser ABI, or query
    ///   sources are invalid.
    public init(
        id: LanguageID,
        displayName: String,
        aliases: Set<LanguageID> = [],
        fileExtensions: Set<String> = [],
        filenames: Set<String> = [],
        treeSitterLanguage: OpaquePointer?,
        highlightsQuery: String,
        injectionsQuery: String? = nil,
        localsQuery: String? = nil
    ) throws(HighlighterError) {
        guard !id.rawValue.isEmpty else {
            throw HighlighterError.emptyLanguageIdentifier
        }
        guard !highlightsQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HighlighterError.missingHighlightsQuery(id)
        }
        guard let treeSitterLanguage else {
            throw HighlighterError.missingParser(id)
        }

        let language = Language(treeSitterLanguage)
        let supportedABI = Language.minimumCompatibleVersion...Language.version
        guard supportedABI.contains(language.ABIVersion) else {
            throw HighlighterError.incompatibleLanguageABI(
                language: id,
                actual: language.ABIVersion,
                supported: supportedABI
            )
        }

        var queries: [Query.Definition: Query] = [:]
        queries[.highlights] = try Self.compile(
            highlightsQuery,
            kind: .highlights,
            languageID: id,
            language: language
        )
        if let injectionsQuery {
            queries[.injections] = try Self.compile(
                injectionsQuery,
                kind: .injections,
                languageID: id,
                language: language
            )
        }
        if let localsQuery {
            queries[.locals] = try Self.compile(
                localsQuery,
                kind: .locals,
                languageID: id,
                language: language
            )
        }

        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.fileExtensions = Set(
            fileExtensions
                .map {
                    LanguageNameNormalizer.fileExtension(from: $0)
                }
                .filter { !$0.isEmpty }
        )
        self.filenames = Set(
            filenames
                .map {
                    LanguageNameNormalizer.filename(from: $0)
                }
                .filter { !$0.isEmpty }
        )
        self.configuration = LanguageConfiguration(
            language,
            name: id.rawValue,
            queries: queries
        )
    }

    /// Compiles a query and translates low-level diagnostics into package
    /// errors.
    ///
    /// - Parameters:
    ///   - source: The Tree-sitter query source.
    ///   - kind: The role the query serves.
    ///   - languageID: The identifier included in diagnostics.
    ///   - language: The parser used to validate query node names.
    /// - Returns: A compiled and reusable Tree-sitter query.
    /// - Throws: ``HighlighterError/invalidQuery(language:kind:message:)`` when
    ///   Tree-sitter rejects the query.
    private static func compile(
        _ source: String,
        kind: LanguageQueryKind,
        languageID: LanguageID,
        language: Language
    ) throws(HighlighterError) -> Query {
        do {
            return try Query(
                language: language,
                data: Data(source.utf8)
            )
        } catch {
            throw HighlighterError.invalidQuery(
                language: languageID,
                kind: kind,
                message: queryErrorDescription(error)
            )
        }
    }

    /// Converts a Tree-sitter query failure into a stable diagnostic.
    ///
    /// - Parameter error: The error emitted while compiling a query.
    /// - Returns: A description that preserves the reported source offset.
    private static func queryErrorDescription(_ error: any Error) -> String {
        guard let queryError = error as? QueryError else {
            return String(describing: error)
        }

        switch queryError {
        case .none:
            return "Tree-sitter reported an unspecified query failure."
        case .syntax(let offset):
            return "The query has invalid syntax at UTF-8 offset \(offset)."
        case .nodeType(let offset):
            return "The query names an unknown node type at UTF-8 offset \(offset)."
        case .field(let offset):
            return "The query names an unknown field at UTF-8 offset \(offset)."
        case .capture(let offset):
            return "The query has an invalid capture at UTF-8 offset \(offset)."
        case .structure(let offset):
            return "The query has an invalid structure at UTF-8 offset \(offset)."
        case .unknown(let offset):
            return "Tree-sitter reported an unknown query error at UTF-8 offset \(offset)."
        }
    }
}
