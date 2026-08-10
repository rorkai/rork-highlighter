# Bundled Languages

Use common Tree-sitter grammars without adding parser packages to an app.

## Available languages

The standard catalog exposes every bundled definition as a typed
``LanguageID`` value. Aliases work anywhere an identifier is accepted. File
discovery applies when source is highlighted through a file URL.

| Language | `LanguageID` | Aliases | File discovery |
| --- | --- | --- | --- |
| Astro | `.astro` | None | `.astro` |
| Bash | `.bash` | `sh`, `shell` | `.bash`, `.bats`, `.sh`, `.zsh`, `.bash_profile`, `.bashrc`, `.profile`, `.zprofile`, `.zshrc` |
| C | `.c` | None | `.c`, `.h` |
| C++ | `.cpp` | `c++`, `cplusplus`, `cxx` | `.cc`, `.cpp`, `.cxx`, `.hh`, `.hpp`, `.hxx`, `.ipp`, `.tpp` |
| CSS | `.css` | None | `.css` |
| Dockerfile | `.dockerfile` | `docker` | `Containerfile`, `Dockerfile` |
| dotenv | `.dotenv` | `env` | `.env`, `.env.development`, `.env.example`, `.env.local`, `.env.production`, `.env.test` |
| Go | `.go` | `golang` | `.go` |
| GraphQL | `.graphql` | `gql` | `.gql`, `.graphql`, `.graphqls` |
| Groovy | `.groovy` | None | `.gradle`, `.groovy`, `.gsh`, `.gvy`, `.gy` |
| HTML | `.html` | `htm` | `.htm`, `.html`, `.xhtml` |
| Java | `.java` | None | `.java` |
| JavaScript | `.javascript` | `js`, `jsx`, `node` | `.cjs`, `.js`, `.jsx`, `.mjs` |
| JSDoc | `.jsdoc` | `js-doc` | None |
| JSON | `.json` | None | `.geojson`, `.json`, `Package.resolved` |
| JSON5 | `.json5` | `jsonc` | `.json5`, `.jsonc`, `jsconfig.json`, `tsconfig.json` |
| Kotlin | `.kotlin` | `kt`, `kts` | `.kt`, `.kts` |
| Markdown | `.markdown` | `md` | `.markdown`, `.md`, `.mdown`, `.mkd`, `.mkdn` |
| Markdown Inline | `.markdownInline` | `markdown_inline` | None |
| MDX | `.mdx` | None | `.mdx` |
| Objective-C | `.objectiveC` | `obj-c`, `objc` | `.m`, `.mm` |
| Java Properties | `.properties` | `java-properties` | `.properties` |
| Python | `.python` | `py` | `.py`, `.pyi`, `.pyw` |
| Regular Expression | `.regex` | `regexp` | None |
| Ruby | `.ruby` | `rb` | `.gemspec`, `.podspec`, `.rake`, `.rb`, `Brewfile`, `Fastfile`, `Gemfile`, `Podfile`, `Rakefile` |
| Rust | `.rust` | `rs` | `.rs` |
| SCSS | `.scss` | None | `.scss` |
| SQL | `.sql` | None | `.sql` |
| Svelte | `.svelte` | None | `.svelte` |
| Swift | `.swift` | `swiftlang` | `.swift` |
| TOML | `.toml` | None | `.toml` |
| TSX | `.tsx` | `react-typescript` | `.tsx` |
| TypeScript | `.typescript` | `ts` | `.cts`, `.mts`, `.ts` |
| Vue | `.vue` | None | `.vue` |
| XML | `.xml` | None | `.plist`, `.storyboard`, `.svg`, `.xib`, `.xml` |
| YAML | `.yaml` | `yml` | `.yaml`, `.yml`, `Podfile.lock` |

## Select a language

Every bundled language has a typed ``LanguageID`` value:

```swift
import RorkHighlighter

let highlighter = try Highlighter()
let swift = try highlighter.highlight(
    "let enabled = true",
    as: .swift
)
let typescript = try highlighter.highlight(
    "const enabled: boolean = true",
    as: .typescript
)
let shell = try highlighter.highlight(
    "enabled=true",
    as: .bash
)
```

``LanguageCatalog/standard()`` also resolves aliases such as `js`, `sh`, `md`,
and `yml`. File URL highlighting uses the same filename and extension metadata.

The common pack covers React Native and Expo sources, Apple and Android native
code, mobile build tooling, and mainstream web formats.

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

Generated parser and scanner files are native code compiled into the internal
`CRorkHighlighterParsers` target. Query files are bundled resources loaded by
`RorkHighlighter`. Apps depend on one library product and only import
`RorkHighlighter`.
