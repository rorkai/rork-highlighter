# Bundled Languages

Use common Tree-sitter grammars without adding parser packages to an app.

## Select a language

Every bundled language has a typed ``LanguageID`` value:

```swift
let swift = try highlighter.highlight(source, as: .swift)
let typescript = try highlighter.highlight(source, as: .typescript)
let shell = try highlighter.highlight(source, as: .bash)
```

``LanguageCatalog/standard()`` also resolves aliases such as `js`, `sh`, `md`,
and `yml`. File URL highlighting uses the same filename and extension metadata.

The common pack covers React Native and Expo sources, Apple and Android native
code, mobile build tooling, and mainstream web formats. It includes JavaScript,
TypeScript, TSX, Swift, Objective-C, Java, Kotlin, Groovy, Ruby, HTML, CSS,
SCSS, Vue, Svelte, Astro, GraphQL, SQL, JSON, JSON5, YAML, TOML, XML, Markdown,
MDX, Dockerfile, dotenv, and supporting languages.

## Highlight nested languages

Injection queries resolve through the complete standard catalog. HTML and
single-file web components select their script and style parsers. Tagged
JavaScript templates can select languages such as GraphQL and SQL. Markdown
inline content, fenced code, HTML blocks, YAML metadata, and TOML metadata use
their matching parsers when present.

```swift
let markdown = """
    # Example

    ```swift
    let enabled = true
    ```
    """

let snapshot = try highlighter.highlight(markdown, as: .markdown)
```

## Understand distribution

Generated parser and scanner files are native code supplied by a precompiled
artifact or the internal `CRorkHighlighterSourceParsers` target. The generated
catalog selects the module available for its destination. Query files are
bundled resources loaded by `RorkHighlighter`. Apps depend on one library
product and only import `RorkHighlighter`.
