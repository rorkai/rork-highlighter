# Architecture

Rork Highlighter separates parser distribution from document highlighting.
The public API should remain stable as the bundled catalog grows and parser
sources move between source and binary distribution.

## Public values

`LanguageID` and `LanguageCatalog` resolve canonical identifiers, aliases,
filenames, and file extensions without exposing mutable parser state.

`HighlightSnapshot`, `HighlightSpan`, and `UTF16Range` are immutable `Sendable`
values. Highlight ranges use UTF-16 because Foundation text systems and the
SwiftTreeSitter convenience API share that coordinate space.

## Parser ownership

One-shot highlighting creates an isolated language layer for each call.
`HighlightSession` owns a persistent language layer inside an actor. The actor
serializes edits and keeps mutable Tree-sitter state from crossing concurrency
boundaries.

An incremental edit updates the existing syntax tree before reparsing. The
first implementation queries a complete snapshot after each edit and also
returns Tree-sitter invalidation ranges. A future renderer can replace the
complete query with visible-range and token-delta processing without changing
edit semantics.

## Language definitions

`HighlightLanguage` combines a process-lifetime parser pointer with immutable
metadata and query sources. It validates the parser ABI and compiles every
query during initialization.

Injection names pass through the same catalog alias resolver as public language
lookups. This keeps names such as `js`, `javascript`, and `tsx` out of
document-specific switch statements.

## Generated packs

`CRorkHighlighterParsers` is one internal Clang target containing every native
parser in the common pack. Each grammar keeps its generated parser header beside
its C sources because Tree-sitter ABI 14 and ABI 15 generated sources use
different structure spellings. The Tree-sitter runtime supports both ABIs.

The public `RorkHighlighter` target contains query resources and generated Swift
catalog wiring. SwiftPM therefore compiles C and Swift in their appropriate
targets while consumers receive one `RorkHighlighter` product and import.

`LanguagePack.json` records upstream repositories, exact revisions, parser entry
points, aliases, filenames, extensions, native files, and query composition.
The update script generates the documented C header and Swift catalog from this
manifest. `LanguagePack.lock.json` records a SHA-256 digest for every managed
output.

Some grammars inherit compatible query fragments from another pinned
repository. TypeScript and TSX use JavaScript fragments, while component
languages reuse matching HTML fragments. The fixture suite compiles each
combined query against its parser before a pack change is accepted.

Two authored translation units wrap the Python and YAML scanners. They isolate
Apple Clang narrowing diagnostics whose values are bounded by Tree-sitter's
fixed serialization buffer. The upstream scanner files remain unmodified and
locked.

Apple application builds must compile and sign parser code at build time.
Downloaded native grammar libraries are not part of the iOS distribution
model. Queries, themes, and other non-executable metadata can have a separate
update policy when compatibility is validated.

## Licensing

Rork-maintained Swift code uses Apache-2.0. Tree-sitter, SwiftTreeSitter, parser
sources, and query files retain their upstream licenses.

The language update rejects licenses outside the approved permissive set. Local
validation then verifies exact checked-in bytes against the generated lock.
