# Architecture

Rork Highlighter separates parser ownership from document highlighting. The
public API remains stable as the bundled catalog and its tooling grow.

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
session retains captures outside the invalidated syntax region and queries only
the changed portion before assembling a complete snapshot. `HighlightUpdate`
also exposes merged rendering ranges so any incremental backend can refresh
only the affected portion of its destination.

## Rendering boundaries

The parser and theme layers do not depend on a presentation framework.
`HighlightRenderer` lets a backend select its own target and typed failure
without prescribing storage, layout, drawing, or font objects.

Native attributed-value functions form a separate Apple convenience layer.
`TextKitHighlightRenderer` is one optimized backend for existing UIKit and
AppKit storage. It does not define the general rendering model and does not own
an editor.

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

The common pack remains source-based on every supported platform. Consumer
benchmarks found that a precompiled parser artifact did not materially improve
fresh or incremental builds once its resolution cost was included. Source
delivery also keeps the package portable and avoids a separate release,
platform-slice, checksum, and fallback pipeline. The distribution benchmark
continues to track clean-build time so this decision can be revisited if the
catalog grows enough to change the tradeoff.

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
