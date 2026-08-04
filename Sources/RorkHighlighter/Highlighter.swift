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
        let documentLength = try validateDocumentLength(text)
        let definition = try languageDefinition(for: language)
        let supportsNestedLanguages =
            definition.configuration.queries[.injections] != nil
            && configuration.maximumInjectionDepth > 0
        if !supportsNestedLanguages || definition.canSkipInjections(in: text) {
            return try makeRootSnapshot(
                text: text,
                language: definition.id,
                configuration: definition.configuration,
                documentLength: documentLength
            )
        }

        let layer = try makeLanguageLayer(for: definition)
        layer.replaceContent(with: text)
        return try makeSnapshot(
            text: text,
            language: definition.id,
            revision: 0,
            layer: layer,
            documentLength: documentLength
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

    /// Parses and queries a document that cannot contain nested languages.
    ///
    /// - Parameters:
    ///   - text: The complete source text.
    ///   - language: The canonical root language identifier.
    ///   - configuration: The compiled parser and query collection.
    ///   - documentLength: The validated UTF-16 source length.
    /// - Returns: A complete immutable highlighting snapshot.
    /// - Throws: ``HighlighterError`` when parsing or querying fails.
    private func makeRootSnapshot(
        text: String,
        language: LanguageID,
        configuration: LanguageConfiguration,
        documentLength: Int
    ) throws(HighlighterError) -> HighlightSnapshot {
        let parser = Parser()

        do {
            try parser.setLanguage(configuration.language)
        } catch {
            throw HighlighterError.parsingFailed(
                language: language,
                message: String(describing: error)
            )
        }
        guard
            let tree = parser.parse(
                tree: Optional<Tree>.none,
                string: text,
                limit: documentLength,
                chunkSize: Self.oneShotParseChunkSize
            )
        else {
            throw HighlighterError.parsingFailed(
                language: language,
                message: "Tree-sitter did not return a syntax tree."
            )
        }
        guard let query = configuration.queries[.highlights] else {
            throw HighlighterError.missingHighlightsQuery(language)
        }

        let cursor = query.execute(in: tree)
        let highlights = makeHighlights(
            from: cursor.resolveCaptureSpansByMatch(
                with: Predicate.Context(string: text)
            ),
            query: query,
            estimatedCapacity: min(
                documentLength / 4,
                Self.maximumOneShotHighlightCapacity
            )
        )
        return HighlightSnapshot(
            parserProducedText: text,
            language: language,
            revision: 0,
            highlights: highlights,
            utf16Length: documentLength
        )
    }

    /// Queries a parsed layer and converts captures into public value types.
    ///
    /// - Parameters:
    ///   - text: The source represented by the layer.
    ///   - language: The canonical root language identifier.
    ///   - revision: The document revision represented by the layer.
    ///   - layer: The parsed root language layer.
    ///   - documentLength: The validated UTF-16 source length.
    /// - Returns: A complete immutable highlighting snapshot.
    /// - Throws: ``HighlighterError`` when the tree or query is unavailable.
    func makeSnapshot(
        text: String,
        language: LanguageID,
        revision: UInt64,
        layer: LanguageLayer,
        documentLength: Int
    ) throws(HighlighterError) -> HighlightSnapshot {
        let fullRange = NSRange(
            location: 0,
            length: documentLength
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
            ),
            utf16Length: documentLength
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
                    text: text
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
    /// - Returns: Highlight spans in deterministic application order.
    /// - Throws: ``LanguageLayerError`` when the highlight query is unavailable.
    private func makeRootHighlights(
        from snapshot: LanguageLayerSnapshot,
        text: String
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
        return makeHighlights(
            from: cursor.resolveCaptureSpansByMatch(
                with: Predicate.Context(string: text)
            ),
            query: query
        )
    }

    /// Converts ordered lightweight captures into public highlight spans.
    ///
    /// - Parameters:
    ///   - captures: The predicate-filtered capture spans in source order.
    ///   - query: The query that owns the capture-name table.
    ///   - estimatedCapacity: The approximate number of output spans.
    /// - Returns: Highlight spans in deterministic application order.
    private func makeHighlights(
        from captures: some Sequence<QueryCaptureSpan>,
        query: Query,
        estimatedCapacity: Int = 0
    ) -> [HighlightSpan] {
        var collector = HighlightCollector(
            estimatedCapacity: estimatedCapacity
        )

        for capture in captures {
            collector.append(capture, query: query)
        }

        return collector.finalize()
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
    /// - Returns: The validated document length in UTF-16 code units.
    /// - Throws: ``HighlighterError/documentTooLarge`` when encoded offsets
    ///   would overflow.
    func validateDocumentLength(
        _ text: String
    ) throws(HighlighterError) -> Int {
        let documentLength = text.utf16.count
        return try validateDocumentLength(documentLength)
    }

    /// Ensures a known UTF-16 length fits the width used by Tree-sitter.
    ///
    /// - Parameter documentLength: The nonnegative UTF-16 document length.
    /// - Returns: The validated document length in UTF-16 code units.
    /// - Throws: ``HighlighterError/documentTooLarge`` when encoded offsets
    ///   would overflow.
    func validateDocumentLength(
        _ documentLength: Int
    ) throws(HighlighterError) -> Int {
        guard documentLength <= Self.maximumUTF16Length else {
            throw HighlighterError.documentTooLarge
        }
        return documentLength
    }

    /// Holds the largest UTF-16 length representable as Tree-sitter byte
    /// offsets.
    private static let maximumUTF16Length = Int(UInt32.max) / 2

    /// Holds the parser read size tuned for complete immutable documents.
    private static let oneShotParseChunkSize = 512 * 1024

    /// Caps speculative output storage for dense one-shot query results.
    private static let maximumOneShotHighlightCapacity = 65_536
}

/// Collects query captures into one deterministically ordered span buffer.
private struct HighlightCollector {
    /// Holds the converted public spans.
    private var highlights: [HighlightSpan] = []

    /// Records whether Tree-sitter emitted spans outside public ordering.
    private var requiresSorting = false

    /// Records whether captures at one source location need local ordering.
    private var requiresLocationGroupOrdering = false

    /// Creates an empty collector with optional storage for expected captures.
    ///
    /// - Parameter estimatedCapacity: The number of captures likely to be stored.
    init(estimatedCapacity: Int = 0) {
        highlights.reserveCapacity(estimatedCapacity)
    }

    /// Appends one query capture when it has a usable scope name.
    ///
    /// - Parameter capture: The Tree-sitter capture to convert.
    mutating func append(_ capture: QueryCapture) {
        append(
            scopeComponents: capture.nameComponents,
            range: capture.range
        )
    }

    /// Appends one lightweight query capture when it has a usable scope name.
    ///
    /// - Parameters:
    ///   - capture: The Tree-sitter capture span to convert.
    ///   - query: The query that owns the capture-name table.
    mutating func append(_ capture: QueryCaptureSpan, query: Query) {
        append(
            scopeComponents:
                query.captureNameComponents(for: capture.index) ?? [],
            range: capture.range
        )
    }

    /// Appends one public highlight value while tracking source order.
    ///
    /// - Parameters:
    ///   - scopeComponents: The semantic hierarchy assigned by the query.
    ///   - range: The capture location in UTF-16 code units.
    private mutating func append(
        scopeComponents: [String],
        range: NSRange
    ) {
        guard !scopeComponents.isEmpty else {
            return
        }

        let highlight = HighlightSpan(
            scopeComponents: scopeComponents,
            range: UTF16Range(
                treeSitterLocation: range.location,
                treeSitterLength: range.length
            )
        )
        if let previousHighlight = highlights.last,
            highlight < previousHighlight
        {
            if highlight.range.location < previousHighlight.range.location {
                requiresSorting = true
            } else {
                requiresLocationGroupOrdering = true
            }
        }
        highlights.append(highlight)
    }

    /// Returns the collected spans in deterministic application order.
    ///
    /// - Returns: The collected spans, sorted only when capture order requires it.
    mutating func finalize() -> [HighlightSpan] {
        if requiresSorting {
            highlights.sort()
        } else if requiresLocationGroupOrdering {
            orderLocationGroups()
        }
        return highlights
    }

    /// Orders captures within source locations using in-place insertion.
    ///
    /// Match-order cursors commonly differ only where overlapping captures
    /// begin together. Keeping those small groups local avoids a complete
    /// document sort.
    private mutating func orderLocationGroups() {
        highlights.withUnsafeMutableBufferPointer { buffer in
            guard buffer.count > 1 else {
                return
            }

            for index in 1..<buffer.count {
                var currentIndex = index
                while currentIndex > 0 {
                    let precedingIndex = currentIndex - 1
                    guard
                        buffer[currentIndex].range.location
                            == buffer[precedingIndex].range.location,
                        buffer[currentIndex] < buffer[precedingIndex]
                    else {
                        break
                    }
                    buffer.swapAt(currentIndex, precedingIndex)
                    currentIndex = precedingIndex
                }
            }
        }
    }
}
