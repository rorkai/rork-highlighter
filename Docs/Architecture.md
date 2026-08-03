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

`CRorkHighlighterSourceParsers` is one internal Clang target containing every
native parser in the common pack. The generated catalog imports this module
when the `CRorkHighlighterParsers` binary module is unavailable. Each grammar
keeps its generated parser header beside its C sources because Tree-sitter ABI
14 and ABI 15 generated sources use different structure spellings. The
Tree-sitter runtime supports both ABIs.

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

## Binary parser artifacts

The Apple binary boundary contains only `CRorkHighlighterParsers`. The stable C
module exposes process-lifetime parser constructors, while the public Swift
API, query resources, themes, and documentation remain source-based. This
avoids rebuilding generated parser tables without coupling clients to a
precompiled Swift toolchain.

`Scripts/build_parser_xcframework.py` compiles the exact C translation units
selected by `Package.swift`. It validates `LanguagePack.lock.json`, builds
static libraries for iOS, macOS, and Mac Catalyst destinations, and combines
them into one XCFramework. Explicit slice arguments remain available for
maintainer experiments. The deterministic ZIP is accompanied by a SwiftPM
checksum and a provenance manifest that records its source, toolchain,
platform matrix, and size.

On macOS hosts, `Package.swift` selects the immutable artifact URL and checksum
recorded in `ParserArtifact.lock.json` for iOS, macOS, and Mac Catalyst.
tvOS, watchOS, and visionOS select the source target through platform
conditions. Other hosts also compile the source target. Artifact generation
and macOS-hosted cross-compilation can request the same source target with
`RORK_HIGHLIGHTER_BUILD_PARSERS_FROM_SOURCE=1`. This switch does not alter the
public package product or Swift import.

The primary pack archive is 26.3 MB and expands to about 273 MiB. The complete
Apple matrix previously required a 60.2 MB archive and about 624 MiB after
extraction. SwiftPM eagerly resolves a remote binary target even when no
product depends on it, so declaring separate platform artifacts in one package
would download all of them. Source fallbacks preserve the remaining Apple
destinations without imposing their binary slices on primary clients.

The artifact retains the package license, third-party notice, and every pinned
grammar license. A local SwiftPM smoke package imports the binary module and
loads all parser constructors before an artifact is accepted. Binary delivery
is a build-time optimization. It does not permit executable parser downloads
after an Apple application has been signed, and non-Apple platforms continue
to require source parsers.

## Licensing

Rork-maintained Swift code uses Apache-2.0. Tree-sitter, SwiftTreeSitter, parser
sources, and query files retain their upstream licenses.

The language update rejects licenses outside the approved permissive set. Local
validation then verifies exact checked-in bytes against the generated lock.
