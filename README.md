# Rork Highlighter

Rork Highlighter is a SwiftPM-first syntax-highlighting library built on
Tree-sitter. It provides a small Swift API for immutable source strings and an
actor-isolated session API for documents that change over time.

![Rork Highlighter rendering Swift with native attributed output.](Sources/RorkHighlighter/RorkHighlighter.docc/Resources/swift-attributed-output.png)

The preview uses the bundled Swift parser and `.rorkDark` theme. The editor
chrome is illustrative.

The package currently bundles a common pack with 36 language definitions. Apps
resolve one Swift package and import one public module instead of managing a
separate SwiftPM dependency for every Tree-sitter grammar.

## Highlights

- Tree-sitter parsing and query-based highlighting.
- Native Swift 6 concurrency and `Sendable` value types.
- Typed `HighlighterError` contracts for highlighting operations.
- Incremental parsing inside one actor per document.
- Explicit UTF-16 ranges that match Foundation text systems.
- Renderer-neutral light and dark themes with hierarchical scope matching.
- A typed renderer contract for native, graphics, terminal, and custom
  backends.
- Native SwiftUI `AttributedString`, TextKit `NSAttributedString`, and an
  optimized incremental TextKit backend.
- Deterministic aliases, filenames, and file-extension discovery.
- Nested-language infrastructure through SwiftTreeSitterLayer.
- A parser-neutral registry for custom and generated language packs.
- One generated Clang target containing all common parser implementations.
- Reproducible grammar updates through exact revisions and locked file hashes.
- Apache-2.0 project code with audited third-party notices.

## Requirements

- Swift 6.0 or newer.
- macOS 13 or newer.
- iOS and Mac Catalyst 16 or newer.
- tvOS 16, watchOS 9, or visionOS 1 when those platforms are relevant.

Tree-sitter and the bundled parser pack also build on supported non-Apple Swift
platforms.

## Installation

Add the package dependency:

```swift
.package(
    url: "https://github.com/rorkai/rork-highlighter.git",
    .upToNextMinor(from: "0.2.1")
)
```

Add the library product to your target:

```swift
.product(
    name: "RorkHighlighter",
    package: "rork-highlighter"
)
```

## One-shot highlighting

Create a highlighter with the bundled catalog and request a snapshot:

```swift
import RorkHighlighter

let highlighter = try Highlighter()
let snapshot = try highlighter.highlight(
    #"{"name":"Rork","enabled":true}"#,
    as: .json
)

for highlight in snapshot.highlights {
    print(highlight.scope, highlight.range)
}
```

The spans preserve Tree-sitter capture names such as
`string.special.key`, `string`, and `constant.builtin`. Spans may overlap.
Apply broader spans first and more specific spans afterward.

## Rendering backends

`HighlightRenderer` defines the common contract for rendering complete
snapshots and incremental updates into a backend target. Renderers choose their
own target, configuration, caching, and typed failure. A backend only needs to
implement complete snapshot rendering because the protocol falls back to the
latest complete snapshot when it receives an update.

Optimized incremental backends can also implement update rendering and use
`HighlightUpdate.rangesRequiringRendering` to refresh the merged replacement
and Tree-sitter invalidation ranges. Raw ordered spans and renderer-neutral
theme styles remain available for Metal, CoreText, terminal, HTML, and other
custom pipelines. See
[Building Rendering Backends](Sources/RorkHighlighter/RorkHighlighter.docc/RenderingBackends.md)
for a complete implementation outline.

Filename and file-extension discovery are also available:

```swift
import Foundation

let snapshot = try highlighter.highlight(
    source,
    for: URL(fileURLWithPath: "/tmp/settings.json")
)
```

## Themes

Resolve highlight spans through a bundled light or dark theme:

```swift
let theme = HighlightTheme.rorkDark

for span in snapshot.highlights {
    let style = theme.style(for: span)
    print(span.range, style)
}
```

Themes are immutable, `Sendable`, and `Codable`. A custom theme supplies a base
style and scope-specific refinements:

```swift
let theme = HighlightTheme(
    name: "Brand",
    baseStyle: HighlightStyle(
        foregroundColor: HighlightColor(rgb: 0xE6_E6_E6),
        textTraits: []
    ),
    styles: [
        "comment": HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x7A_8A_99),
            textTraits: [.italic]
        ),
        "keyword": HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xD9_9B_FF)
        ),
    ]
)
```

Scope matching proceeds from broad captures to specific captures. A
`string.special.key` span inherits `string` and `string.special` refinements
before its exact rule is applied.

## Native attributed output

Highlight Swift source and render the snapshot directly in SwiftUI:

```swift
import RorkHighlighter
import SwiftUI

let source = #"""
import SwiftUI

struct WelcomeView: View {
    let name: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
            Text("Hello, \(name)!")
                .font(.title.bold())
        }
    }
}
"""#

let highlighter = try Highlighter()
let snapshot = try highlighter.highlight(source, as: .swift)
let rendered = try snapshot.attributedString(
    theme: .rorkDark,
    font: .system(size: 15, design: .monospaced)
)

let code = Text(rendered)
    .textSelection(.enabled)
    .padding()
    .background(Color.black)
```

The bundled themes leave `HighlightStyle.backgroundColor` unset. Set the canvas
on the containing view or editor so attributed text does not paint background
strips behind individual text runs.

The renderer uses a monospaced system font by default. Supply any SwiftUI font
when the surrounding interface owns typography:

```swift
let rendered = try snapshot.attributedString(
    theme: .rorkLight,
    font: .system(size: 14, design: .monospaced)
)
```

UIKit and AppKit clients can request an `NSAttributedString` with native
platform colors, fonts, and TextKit keys:

```swift
let rendered = try snapshot.nsAttributedString(
    theme: .rorkDark,
    font: .monospacedSystemFont(ofSize: 14, weight: .regular)
)
```

Assign the result directly to APIs such as `UILabel.attributedText` or
`NSTextStorage.setAttributedString(_:)`.

Use `TextKitHighlightRenderer`, the built-in `HighlightRenderer` backend, when
a text view already owns its attributed storage. It supports the
`NSTextStorage` exposed by TextKit 1 and TextKit 2 while preserving paragraph
styles, links, attachments, and custom attributes.

Rendering preserves the snapshot's UTF-16 ranges and overlap order. Invalid
ranges throw `HighlightRenderingError` instead of being rounded or trapping.
The native APIs are available when SwiftUI, UIKit, or AppKit is present.
Renderer-neutral themes and raw spans remain available on Linux and other
Swift platforms.

## Bundled languages

The standard catalog includes the following definitions:

| Language | Swift identifier | Common aliases | File extensions | Exact filenames |
| --- | --- | --- | --- | --- |
| Astro | `.astro` | | `astro` | |
| Bash | `.bash` | `sh`, `shell` | `bash`, `bats`, `sh`, `zsh` | `.bash_profile`, `.bashrc`, `.profile`, `.zprofile`, `.zshrc` |
| C | `.c` | | `c`, `h` | |
| C++ | `.cpp` | `c++`, `cplusplus`, `cxx` | `cc`, `cpp`, `cxx`, `hh`, `hpp`, `hxx`, `ipp`, `tpp` | |
| CSS | `.css` | | `css` | |
| Dockerfile | `.dockerfile` | `docker` | | `Containerfile`, `Dockerfile` |
| dotenv | `.dotenv` | `env` | `env` | `.env`, `.env.development`, `.env.example`, `.env.local`, `.env.production`, `.env.test` |
| Go | `.go` | `golang` | `go` | |
| GraphQL | `.graphql` | `gql` | `gql`, `graphql`, `graphqls` | |
| Groovy | `.groovy` | | `gradle`, `groovy`, `gsh`, `gvy`, `gy` | |
| HTML | `.html` | `htm` | `htm`, `html`, `xhtml` | |
| Java | `.java` | | `java` | |
| JavaScript | `.javascript` | `js`, `jsx`, `node` | `cjs`, `js`, `jsx`, `mjs` | |
| JSDoc | `.jsdoc` | `js-doc` | | |
| JSON | `.json` | | `geojson`, `json` | `Package.resolved` |
| JSON5 | `.json5` | `jsonc` | `json5`, `jsonc` | `jsconfig.json`, `tsconfig.json` |
| Kotlin | `.kotlin` | `kt`, `kts` | `kt`, `kts` | |
| Markdown | `.markdown` | `md` | `markdown`, `md`, `mdown`, `mkd`, `mkdn` | |
| Markdown Inline | `.markdownInline` | `markdown_inline` | | |
| MDX | `.mdx` | | `mdx` | |
| Objective-C | `.objectiveC` | `obj-c`, `objc` | `m`, `mm` | |
| Java Properties | `.properties` | `java-properties` | `properties` | |
| Python | `.python` | `py` | `py`, `pyi`, `pyw` | |
| Regular Expression | `.regex` | `regexp` | | |
| Ruby | `.ruby` | `rb` | `gemspec`, `podspec`, `rake`, `rb` | `Brewfile`, `Fastfile`, `Gemfile`, `Podfile`, `Rakefile` |
| Rust | `.rust` | `rs` | `rs` | |
| SCSS | `.scss` | | `scss` | |
| SQL | `.sql` | | `sql` | |
| Svelte | `.svelte` | | `svelte` | |
| Swift | `.swift` | `swiftlang` | `swift` | |
| TOML | `.toml` | | `toml` | |
| TSX | `.tsx` | `react-typescript` | `tsx` | |
| TypeScript | `.typescript` | `ts` | `cts`, `mts`, `ts` | |
| Vue | `.vue` | | `vue` | |
| XML | `.xml` | | `plist`, `storyboard`, `svg`, `xib`, `xml` | |
| YAML | `.yaml` | `yml` | `yaml`, `yml` | `Podfile.lock` |

Markdown Inline, JSDoc, and Regular Expression are public because they are real
Tree-sitter definitions. Their primary role is parsing content injected by
Markdown, JavaScript, TypeScript, TSX, and Swift.

## Incremental highlighting

Keep one session and TextKit renderer for each open document:

```swift
let session = try highlighter.makeSession(source, as: .swift)
let renderer = TextKitHighlightRenderer(theme: .rorkDark)
#if canImport(AppKit)
guard let textStorage = textView.textStorage else {
    return
}
#else
let textStorage = textView.textStorage
#endif
let snapshot = try await session.snapshot()
try renderer.render(snapshot, in: textStorage)

let editRange = UTF16Range(location: 10, length: 1)
let replacement = "updated"
textStorage.replaceCharacters(
    in: NSRange(location: editRange.location, length: editRange.length),
    with: replacement
)
let update = try await session.replaceCharacters(
    in: editRange,
    with: replacement
)
try renderer.render(update, in: textStorage)
```

Apply the same character edit to TextKit before rendering its matching update.
The renderer restyles only the replacement and invalidated syntax ranges. It
does not compare the complete source after every update. A skipped revision, a
different storage instance, an incompatible source length, or an appearance
change triggers a verified complete render. Reject same-length out-of-order
edits through the document revision before passing them to the renderer.

Other rendering backends receive the same `HighlightUpdate`. Use
`rangesRequiringRendering` when the destination can update only affected
regions, or rely on the protocol's complete-snapshot fallback.

## Registering a language

`HighlightLanguage` accepts any compatible generated Tree-sitter parser and its
matching query sources:

```swift
import RorkHighlighter
import TreeSitterSwift

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

let catalog = try LanguageCatalog(languages: [swift])
let highlighter = Highlighter(catalog: catalog)
```

Applications do not need to register bundled languages this way. Direct
registration remains available for private grammars and languages outside the
common pack.

## Language distribution

Official language packs follow three rules:

1. Parser code and query files come from the same pinned upstream revision.
2. Every distributed grammar has an audited permissive license.
3. Apple application builds bundle parser code at build time instead of
   downloading executable parsers.

`CRorkHighlighterParsers` is an internal Clang target. Generated `parser.c` and
`scanner.c` files are compiled native code under that target. Matching
`highlights.scm`, `injections.scm`, and `locals.scm` files are resources in the
public Swift target. Consumers only import `RorkHighlighter`.

## Development

Run the complete validation:

```bash
make check
```

Format maintained Swift sources:

```bash
make format
```

`make check` builds with warnings treated as errors, runs the tests, lints
Swift formatting, verifies the language pack lock, and checks documentation for
Swift and authored C declarations. It also compiles the private benchmark and
distribution-measurement tools.

Run the public-workflow performance suite:

```bash
make benchmark
```

Run the opt-in same-corpus comparison with HighlightKit, swift-highlight, and
highlight.js:

```bash
make benchmark-comparison \
  COMPARISON_BENCHMARK_ARGUMENTS="--metric wallClock --time-units microseconds --no-progress"
```

Measure a clean release build and its parser, executable, and resource sizes:

```bash
make measure-distribution
```

The [benchmark guide](Benchmarks/README.md) describes the regression workloads,
reported metrics, focused runs, cross-library comparison suite, and
machine-comparison constraints.

Update every bundled parser from its pinned revision:

```bash
make vendor-languages
```

The update command reads `LanguagePack.json`, regenerates the C interface and
Swift catalog, copies exact upstream files, and refreshes
`LanguagePack.lock.json`.

See the package's DocC catalog for API guidance, the
[architecture](Docs/Architecture.md) for the distribution design, the
[roadmap](Docs/Roadmap.md) for planned work, and the
[contribution guide](CONTRIBUTING.md) for maintenance rules. The
[changelog](CHANGELOG.md) records each published release.

## License

Rork Highlighter is licensed under Apache-2.0. Tree-sitter,
SwiftTreeSitter, and bundled grammars retain their original permissive
licenses. See `THIRD_PARTY_NOTICES.md` for exact attribution.
