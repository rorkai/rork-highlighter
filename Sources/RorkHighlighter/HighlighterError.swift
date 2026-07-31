import Foundation

/// Describes failures produced while configuring or running a highlighter.
public enum HighlighterError: Error, Equatable, Sendable {
    /// A language or alias normalized to an empty identifier.
    case emptyLanguageIdentifier

    /// Two definitions attempted to register the same canonical identifier.
    case duplicateLanguage(LanguageID)

    /// Two definitions attempted to register the same alias.
    case duplicateAlias(LanguageID)

    /// Two definitions attempted to claim the same file extension.
    case duplicateFileExtension(String)

    /// Two definitions attempted to claim the same complete filename.
    case duplicateFilename(String)

    /// No registered definition matched the requested identifier.
    case unknownLanguage(LanguageID)

    /// A language did not provide the query required for highlighting.
    case missingHighlightsQuery(LanguageID)

    /// A query could not be compiled for its associated parser.
    case invalidQuery(
        language: LanguageID,
        kind: LanguageQueryKind,
        message: String
    )

    /// A parser uses a Tree-sitter ABI unsupported by the linked runtime.
    case incompatibleLanguageABI(
        language: LanguageID,
        actual: Int,
        supported: ClosedRange<Int>
    )

    /// A bundled parser or query resource could not be loaded.
    case missingResource(String)

    /// A bundled query resource exists but cannot be read.
    case unreadableResource(resource: String, message: String)

    /// An unexpected error prevented the standard catalog from initializing.
    case bundledCatalogInitializationFailed(message: String)

    /// A language definition did not receive a compiled parser pointer.
    case missingParser(LanguageID)

    /// Tree-sitter could not create or update a syntax tree.
    case parsingFailed(language: LanguageID, message: String)

    /// Query execution failed after a syntax tree was available.
    case highlightingFailed(language: LanguageID, message: String)

    /// A UTF-16 range extends beyond the current text.
    case rangeOutOfBounds(range: UTF16Range, textLength: Int)

    /// A UTF-16 range splits a Unicode scalar and cannot edit a Swift string.
    case invalidUTF16Boundary(UTF16Range)

    /// The document exceeds the offset width supported by Tree-sitter.
    case documentTooLarge
}

/// Supplies localized descriptions without losing structured error cases.
extension HighlighterError: LocalizedError {
    /// Provides a stable, human-readable explanation for logs and user
    /// interfaces.
    public var errorDescription: String? {
        switch self {
        case .emptyLanguageIdentifier:
            "Language identifiers cannot be empty."
        case .duplicateLanguage(let language):
            "The language catalog contains more than one '\(language)' definition."
        case .duplicateAlias(let alias):
            "The language alias '\(alias)' belongs to more than one definition."
        case .duplicateFileExtension(let fileExtension):
            "The file extension '\(fileExtension)' belongs to more than one definition."
        case .duplicateFilename(let filename):
            "The filename '\(filename)' belongs to more than one definition."
        case .unknownLanguage(let language):
            "The language catalog does not contain '\(language)'."
        case .missingHighlightsQuery(let language):
            "The '\(language)' definition does not contain a highlights query."
        case .invalidQuery(let language, let kind, let message):
            "The \(kind.rawValue) query for '\(language)' is invalid. \(message)"
        case .incompatibleLanguageABI(let language, let actual, let supported):
            "The '\(language)' parser uses ABI \(actual), but this runtime supports \(supported)."
        case .missingResource(let resource):
            "The bundled resource '\(resource)' is unavailable."
        case .unreadableResource(let resource, let message):
            "The bundled resource '\(resource)' could not be read. \(message)"
        case .bundledCatalogInitializationFailed(let message):
            "The bundled language catalog could not be initialized. \(message)"
        case .missingParser(let language):
            "The '\(language)' definition does not contain a compiled parser."
        case .parsingFailed(let language, let message):
            "Tree-sitter could not parse the '\(language)' document. \(message)"
        case .highlightingFailed(let language, let message):
            "Highlighting the '\(language)' document failed. \(message)"
        case .rangeOutOfBounds(let range, let textLength):
            "The UTF-16 range \(range) exceeds the document length of \(textLength)."
        case .invalidUTF16Boundary(let range):
            "The UTF-16 range \(range) splits a Unicode scalar."
        case .documentTooLarge:
            "The document is too large for Tree-sitter's 32-bit offsets."
        }
    }
}
