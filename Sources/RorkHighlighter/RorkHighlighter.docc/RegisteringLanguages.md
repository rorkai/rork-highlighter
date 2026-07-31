# Registering Languages

Connect a generated Tree-sitter parser to Rork Highlighter.

The standard catalog already includes the common parser pack. Use direct
registration for a private grammar or a language outside that pack.

## Create a definition

A definition combines parser code, discovery metadata, and matching query
sources:

```swift
let swift = try HighlightLanguage(
    id: "swift",
    displayName: "Swift",
    aliases: ["swiftlang"],
    fileExtensions: ["swift"],
    filenames: [],
    treeSitterLanguage: tree_sitter_swift(),
    highlightsQuery: swiftHighlightsQuery,
    injectionsQuery: swiftInjectionsQuery
)
```

The initializer compiles every query immediately. A query that names nodes from
a different grammar revision therefore fails before source text is opened.

## Build a catalog

Create a deterministic catalog from one or more definitions:

```swift
let catalog = try LanguageCatalog(languages: [swift])
let highlighter = Highlighter(catalog: catalog)
```

Catalog construction rejects duplicate identifiers, aliases, file extensions,
and exact filenames. Injection queries use the same alias lookup when resolving
nested languages.

The official common pack compiles its parsers behind one SwiftPM product and
constructs its catalog automatically.
