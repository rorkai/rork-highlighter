import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

/// Creates one-shot highlights and incremental document sessions.
///
/// `Highlighter` is immutable and safe to share across tasks. Each one-shot
/// operation creates its own parser state, while ``HighlightSession`` owns
/// mutable state inside an actor.
public struct Highlighter: Sendable {
    /// Holds the immutable language definitions available to the highlighter.
    public let catalog: LanguageCatalog

    /// Holds behavior shared by new highlighting operations.
    public let configuration: HighlighterConfiguration

    /// Creates a highlighter with the package's bundled language catalog.
    ///
    /// - Parameter configuration: Behavior shared by highlighting operations.
    /// - Throws: ``HighlighterError`` when a bundled parser or query cannot be
    ///   loaded.
    public init(
        configuration: HighlighterConfiguration = .default
    ) throws {
        self.init(
            catalog: try .standard(),
            configuration: configuration
        )
    }

    /// Creates a highlighter with an explicit language catalog.
    ///
    /// - Parameters:
    ///   - catalog: The languages available to highlighting operations.
    ///   - configuration: Behavior shared by highlighting operations.
    public init(
        catalog: LanguageCatalog,
        configuration: HighlighterConfiguration = .default
    ) {
        self.catalog = catalog
        self.configuration = configuration
    }

    /// Highlights an immutable source string in one operation.
    ///
    /// - Parameters:
    ///   - text: The complete source text.
    ///   - language: The canonical identifier or alias of the root language.
    /// - Returns: A snapshot containing the source and ordered highlight spans.
    /// - Throws: ``HighlighterError`` when the language is unavailable or
    ///   Tree-sitter cannot process the document.
    public func highlight(
        _ text: String,
        as language: LanguageID
    ) throws -> HighlightSnapshot {
        try validateDocumentLength(text)
        let definition = try languageDefinition(for: language)
        let layer = try makeLanguageLayer(for: definition)
        layer.replaceContent(with: text)
        return try makeSnapshot(
            text: text,
            language: definition.id,
            revision: 0,
            layer: layer
        )
    }

    /// Highlights an immutable source string using its filename or extension.
    ///
    /// - Parameters:
    ///   - text: The complete source text.
    ///   - fileURL: The source file whose name identifies its language.
    /// - Returns: A snapshot containing the source and ordered highlight spans.
    /// - Throws: ``HighlighterError`` when the file type is unknown or
    ///   Tree-sitter cannot process the document.
    public func highlight(
        _ text: String,
        for fileURL: URL
    ) throws -> HighlightSnapshot {
        guard let language = catalog.language(for: fileURL) else {
            let unresolvedName =
                fileURL.pathExtension.isEmpty
                ? fileURL.lastPathComponent
                : fileURL.pathExtension
            throw HighlighterError.unknownLanguage(
                LanguageID(unresolvedName)
            )
        }
        return try highlight(text, as: language.id)
    }

    /// Opens an actor-isolated session for a changing source string.
    ///
    /// - Parameters:
    ///   - text: The initial source text.
    ///   - language: The canonical identifier or alias of the root language.
    /// - Returns: A session that incrementally reparses later edits.
    /// - Throws: ``HighlighterError`` when the language is unavailable or the
    ///   initial document cannot be parsed.
    public func makeSession(
        _ text: String,
        as language: LanguageID
    ) throws -> HighlightSession {
        try HighlightSession(
            highlighter: self,
            text: text,
            language: language
        )
    }

    /// Resolves a requested identifier to its canonical definition.
    ///
    /// - Parameter identifier: The canonical identifier or alias to resolve.
    /// - Returns: The matching language definition.
    /// - Throws: ``HighlighterError/unknownLanguage(_:)`` when no definition
    ///   matches.
    func languageDefinition(
        for identifier: LanguageID
    ) throws -> HighlightLanguage {
        guard let language = catalog.language(for: identifier) else {
            throw HighlighterError.unknownLanguage(identifier)
        }
        return language
    }

    /// Creates an isolated language layer with catalog-backed injection lookup.
    ///
    /// - Parameter language: The root language for the new layer.
    /// - Returns: A mutable layer that has not parsed source text yet.
    /// - Throws: ``HighlighterError/parsingFailed(language:message:)`` when
    ///   Tree-sitter rejects the parser configuration.
    func makeLanguageLayer(
        for language: HighlightLanguage
    ) throws -> LanguageLayer {
        let layerConfiguration = LanguageLayer.Configuration(
            maximumLanguageDepth: configuration.maximumInjectionDepth
        ) { injectedName in
            catalog
                .language(for: LanguageID(injectedName))?
                .configuration
        }

        do {
            return try LanguageLayer(
                languageConfig: language.configuration,
                configuration: layerConfiguration
            )
        } catch {
            throw HighlighterError.parsingFailed(
                language: language.id,
                message: String(describing: error)
            )
        }
    }

    /// Queries a parsed layer and converts captures into public value types.
    ///
    /// - Parameters:
    ///   - text: The source represented by the layer.
    ///   - language: The canonical root language identifier.
    ///   - revision: The document revision represented by the layer.
    ///   - layer: The parsed root language layer.
    /// - Returns: A complete immutable highlighting snapshot.
    /// - Throws: ``HighlighterError`` when the tree or query is unavailable.
    func makeSnapshot(
        text: String,
        language: LanguageID,
        revision: UInt64,
        layer: LanguageLayer
    ) throws -> HighlightSnapshot {
        let fullRange = NSRange(
            location: 0,
            length: text.utf16.count
        )

        do {
            let ranges = try layer.highlights(
                in: fullRange,
                provider: text.predicateTextProvider
            )
            let highlights =
                ranges
                .map { range in
                    HighlightSpan(
                        scopeComponents: range.nameComponents,
                        range: UTF16Range(
                            location: range.range.location,
                            length: range.range.length
                        )
                    )
                }
                .sorted()
            return HighlightSnapshot(
                text: text,
                language: language,
                revision: revision,
                highlights: highlights
            )
        } catch LanguageLayerError.noRootNode {
            throw HighlighterError.parsingFailed(
                language: language,
                message: "Tree-sitter produced no root syntax node."
            )
        } catch {
            throw HighlighterError.highlightingFailed(
                language: language,
                message: String(describing: error)
            )
        }
    }

    /// Ensures UTF-16 offsets fit the width used by Tree-sitter.
    ///
    /// - Parameter text: The document to validate.
    /// - Throws: ``HighlighterError/documentTooLarge`` when encoded offsets
    ///   would overflow.
    func validateDocumentLength(_ text: String) throws {
        guard text.utf16.count <= Self.maximumUTF16Length else {
            throw HighlighterError.documentTooLarge
        }
    }

    /// Holds the largest UTF-16 length representable as Tree-sitter byte
    /// offsets.
    private static let maximumUTF16Length = Int(UInt32.max) / 2
}
