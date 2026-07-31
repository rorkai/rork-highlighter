import Foundation

/// Stores immutable language definitions and their discovery metadata.
///
/// Catalog construction rejects ambiguous aliases, file extensions, and
/// filenames so language resolution stays deterministic.
public struct LanguageCatalog: Sendable {
    /// Holds the definitions in canonical identifier order.
    public let languages: [HighlightLanguage]

    /// Provides constant-time lookup for canonical identifiers.
    private let languagesByID: [LanguageID: HighlightLanguage]

    /// Maps canonical identifiers and aliases to their owning definitions.
    private let identifiers: [LanguageID: LanguageID]

    /// Maps normalized file extensions to canonical identifiers.
    private let fileExtensions: [String: LanguageID]

    /// Maps normalized filenames to canonical identifiers.
    private let filenames: [String: LanguageID]

    /// Creates a deterministic catalog from language definitions.
    ///
    /// - Parameter languages: The definitions available to a highlighter.
    /// - Throws: ``HighlighterError`` when an identifier is empty or discovery
    ///   metadata is ambiguous.
    public init(
        languages: [HighlightLanguage]
    ) throws(HighlighterError) {
        var languagesByID: [LanguageID: HighlightLanguage] = [:]
        var identifiers: [LanguageID: LanguageID] = [:]
        var fileExtensions: [String: LanguageID] = [:]
        var filenames: [String: LanguageID] = [:]

        for language in languages {
            guard !language.id.rawValue.isEmpty else {
                throw HighlighterError.emptyLanguageIdentifier
            }
            guard languagesByID[language.id] == nil else {
                throw HighlighterError.duplicateLanguage(language.id)
            }
            languagesByID[language.id] = language

            for identifier in language.aliases.union([language.id]) {
                guard !identifier.rawValue.isEmpty else {
                    throw HighlighterError.emptyLanguageIdentifier
                }
                if let existing = identifiers[identifier], existing != language.id {
                    throw HighlighterError.duplicateAlias(identifier)
                }
                identifiers[identifier] = language.id
            }

            for fileExtension in language.fileExtensions {
                guard !fileExtension.isEmpty else {
                    continue
                }
                if let existing = fileExtensions[fileExtension], existing != language.id {
                    throw HighlighterError.duplicateFileExtension(fileExtension)
                }
                fileExtensions[fileExtension] = language.id
            }

            for filename in language.filenames {
                guard !filename.isEmpty else {
                    continue
                }
                if let existing = filenames[filename], existing != language.id {
                    throw HighlighterError.duplicateFilename(filename)
                }
                filenames[filename] = language.id
            }
        }

        self.languages = languages.sorted { $0.id < $1.id }
        self.languagesByID = languagesByID
        self.identifiers = identifiers
        self.fileExtensions = fileExtensions
        self.filenames = filenames
    }

    /// Returns the definition matching a canonical identifier or alias.
    ///
    /// - Parameter identifier: The identifier supplied by a caller or query.
    /// - Returns: The matching definition, or `nil` when no language matches.
    public func language(for identifier: LanguageID) -> HighlightLanguage? {
        guard let canonicalID = identifiers[identifier] else {
            return nil
        }
        return languagesByID[canonicalID]
    }

    /// Returns the definition associated with a file extension.
    ///
    /// The lookup ignores case and accepts extensions with or without a leading
    /// period.
    ///
    /// - Parameter fileExtension: The extension to resolve.
    /// - Returns: The matching definition, or `nil` when no language matches.
    public func language(forFileExtension fileExtension: String) -> HighlightLanguage? {
        let normalizedExtension = LanguageNameNormalizer.fileExtension(
            from: fileExtension
        )
        guard let canonicalID = fileExtensions[normalizedExtension] else {
            return nil
        }
        return languagesByID[canonicalID]
    }

    /// Returns the definition associated with a complete filename.
    ///
    /// Exact filename metadata is checked before the filename's extension.
    /// Both lookups ignore case.
    ///
    /// - Parameter filename: The complete source filename to resolve.
    /// - Returns: The matching definition, or `nil` when no language matches.
    public func language(forFilename filename: String) -> HighlightLanguage? {
        let normalizedFilename = LanguageNameNormalizer.filename(
            from: filename
        )
        if let canonicalID = filenames[normalizedFilename] {
            return languagesByID[canonicalID]
        }
        return language(
            forFileExtension: (normalizedFilename as NSString).pathExtension
        )
    }

    /// Returns the definition associated with a file URL.
    ///
    /// - Parameter fileURL: The source file whose name should be resolved.
    /// - Returns: The matching definition, or `nil` when no language matches.
    public func language(for fileURL: URL) -> HighlightLanguage? {
        language(forFilename: fileURL.lastPathComponent)
    }
}
