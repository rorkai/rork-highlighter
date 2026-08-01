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
    /// - Parameter configuration: The behavior shared by highlighting operations.
    /// - Throws: ``HighlighterError`` when a bundled parser or query cannot be
    ///   loaded.
    public init(
        configuration: HighlighterConfiguration = .default
    ) throws(HighlighterError) {
        self.init(
            catalog: try .standard(),
            configuration: configuration
        )
    }

    /// Creates a highlighter with an explicit language catalog.
    ///
    /// - Parameters:
    ///   - catalog: The languages available to highlighting operations.
    ///   - configuration: The behavior shared by highlighting operations.
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
    ) throws(HighlighterError) -> HighlightSnapshot {
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
    ) throws(HighlighterError) -> HighlightSnapshot {
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
    ) throws(HighlighterError) -> HighlightSession {
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
    ) throws(HighlighterError) -> HighlightLanguage {
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
    ) throws(HighlighterError) -> LanguageLayer {
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
    ) throws(HighlighterError) -> HighlightSnapshot {
        let fullRange = NSRange(
            location: 0,
            length: text.utf16.count
        )

        return HighlightSnapshot(
            parserProducedText: text,
            language: language,
            revision: revision,
            highlights: try makeHighlights(
                text: text,
                language: language,
                layer: layer,
                in: fullRange
            )
        )
    }

    /// Queries a parsed layer and converts captures with one ordered buffer.
    ///
    /// SwiftTreeSitter's convenience API first sorts query captures into an
    /// intermediate `NamedRange` array. Rork Highlighter needs its own public
    /// value type and ordering, so collecting captures directly avoids an
    /// intermediate allocation and a redundant sort.
    ///
    /// - Parameters:
    ///   - text: The source represented by the layer.
    ///   - language: The canonical root language identifier.
    ///   - layer: The parsed root language layer.
    ///   - range: The UTF-16 region whose intersecting captures are requested.
    /// - Returns: Highlight spans in deterministic application order.
    /// - Throws: ``HighlighterError`` when the tree or query is unavailable.
    func makeHighlights(
        text: String,
        language: LanguageID,
        layer: LanguageLayer,
        in range: NSRange
    ) throws(HighlighterError) -> [HighlightSpan] {
        guard range.length > 0 else {
            return []
        }

        do {
            let queryRange = IndexSet(
                integersIn: range.location..<(range.location + range.length)
            )
            guard let snapshot = layer.snapshot(in: queryRange) else {
                throw LanguageLayerError.noRootNode
            }

            if snapshot.sublayerSnapshots.isEmpty,
                range.location == 0,
                range.length == text.utf16.count
            {
                return try makeRootHighlights(
                    from: snapshot.rootSnapshot,
                    text: text,
                    in: range
                )
            }

            return makeHighlights(
                from: try snapshot.executeQuery(
                    .highlights,
                    in: queryRange
                ),
                text: text
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

    /// Streams a complete root query without allocating intermediate matches.
    ///
    /// Tree-sitter's ordered capture cursor omits captures outside a bounded
    /// query range. This path therefore handles complete documents only, while
    /// bounded incremental refreshes retain the general match cursor.
    ///
    /// - Parameters:
    ///   - snapshot: The root language snapshot containing the parsed tree.
    ///   - text: The complete source text used to resolve query predicates.
    ///   - range: The complete UTF-16 document range.
    /// - Returns: Highlight spans in deterministic application order.
    /// - Throws: ``LanguageLayerError`` when the highlight query is unavailable.
    private func makeRootHighlights(
        from snapshot: LanguageLayerSnapshot,
        text: String,
        in range: NSRange
    ) throws(LanguageLayerError) -> [HighlightSpan] {
        guard let query = snapshot.data.queries[.highlights] else {
            throw LanguageLayerError.queryUnavailable(
                snapshot.data.name,
                .highlights
            )
        }

        let cursor = query.execute(
            in: snapshot.tree,
            depth: snapshot.depth
        )
        cursor.setRange(range)
        return makeHighlights(
            from: cursor.resolveCaptures(
                with: Predicate.Context(string: text)
            )
        )
    }

    /// Converts ordered query captures into public highlight spans.
    ///
    /// - Parameter captures: The predicate-filtered captures in source order.
    /// - Returns: Highlight spans in deterministic application order.
    private func makeHighlights(
        from captures: some Sequence<QueryCapture>
    ) -> [HighlightSpan] {
        var collector = HighlightCollector()

        for capture in captures {
            collector.append(capture)
        }

        return collector.finalize()
    }

    /// Converts resolved query captures into ordered public spans.
    ///
    /// - Parameters:
    ///   - matches: The query matches produced by one or more language layers.
    ///   - text: The source used to evaluate query predicates.
    /// - Returns: Highlight spans in deterministic application order.
    private func makeHighlights(
        from matches: some Sequence<QueryMatch>,
        text: String
    ) -> [HighlightSpan] {
        let resolvedMatches = matches.resolve(
            with: Predicate.Context(string: text)
        )
        var collector = HighlightCollector()

        for match in resolvedMatches {
            for capture in match.captures {
                collector.append(capture)
            }
        }

        return collector.finalize()
    }

    /// Ensures UTF-16 offsets fit the width used by Tree-sitter.
    ///
    /// - Parameter text: The document to validate.
    /// - Throws: ``HighlighterError/documentTooLarge`` when encoded offsets
    ///   would overflow.
    func validateDocumentLength(
        _ text: String
    ) throws(HighlighterError) {
        guard text.utf16.count <= Self.maximumUTF16Length else {
            throw HighlighterError.documentTooLarge
        }
    }

    /// Holds the largest UTF-16 length representable as Tree-sitter byte
    /// offsets.
    private static let maximumUTF16Length = Int(UInt32.max) / 2
}

/// Collects query captures into one deterministically ordered span buffer.
private struct HighlightCollector {
    /// Holds the converted public spans.
    private var highlights: [HighlightSpan] = []

    /// Holds the previously appended span for the ordering check.
    private var previousHighlight: HighlightSpan?

    /// Records whether Tree-sitter emitted spans outside public ordering.
    private var requiresSorting = false

    /// Appends one query capture when it has a usable scope name.
    ///
    /// - Parameter capture: The Tree-sitter capture to convert.
    mutating func append(_ capture: QueryCapture) {
        guard !capture.nameComponents.isEmpty else {
            return
        }

        let captureRange = capture.range
        let highlight = HighlightSpan(
            scopeComponents: capture.nameComponents,
            range: UTF16Range(
                location: captureRange.location,
                length: captureRange.length
            )
        )
        if let previousHighlight, highlight < previousHighlight {
            requiresSorting = true
        }
        highlights.append(highlight)
        previousHighlight = highlight
    }

    /// Returns the collected spans in deterministic application order.
    ///
    /// - Returns: The collected spans, sorted only when capture order requires it.
    mutating func finalize() -> [HighlightSpan] {
        if requiresSorting {
            highlights.sort()
        }
        return highlights
    }
}
