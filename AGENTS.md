# Rork Highlighter

Rork Highlighter is a SwiftPM-first syntax-highlighting library built on
Tree-sitter.

## Swift code

Follow the Swift API Design Guidelines and use Swift 6 language mode. Public
APIs should read naturally at the call site, preserve concrete error context,
and make ownership and concurrency behavior explicit.

Every maintained Swift declaration must have a DocC comment. This includes
private and internal types, stored properties, computed properties,
initializers, methods, enum cases, test helpers, and test functions. Generated
or vendored sources are exempt because their upstream project owns them.

Comments and documentation use short, complete prose. Do not use
label-and-fragment colon patterns, semicolon-joined clauses, or em dashes.
Comments explain design intent and non-obvious constraints instead of repeating
the implementation.

Keep mutable Tree-sitter objects inside an actor or another explicitly
serialized owner. Values that cross concurrency boundaries must conform to
`Sendable` honestly.

## Package structure

Use `Package.swift` as the source of truth. Do not commit `.build`,
`Package.resolved`, Xcode-generated projects, or derived documentation output.

Keep public Swift code under `Sources/RorkHighlighter`. Keep generated language
parser sources under the internal `CRorkHighlighterParsers` target. A language
parser and its query files must come from compatible pinned upstream revisions.

Every declaration in an authored C header requires consecutive `///`
documentation lines. Generated and vendored C sources keep their upstream bytes
and are exempt. Authored C translation units begin with consecutive `///`
documentation lines explaining why the file exists.

Each bundled parser requires an audited permissive license and an entry in
`THIRD_PARTY_NOTICES.md`. Do not add a grammar with an absent, ambiguous,
noncommercial, or copyleft license to an official language pack.

## Validation

Run the complete local validation before finishing:

```bash
make check
```

Use `make format` when formatting changes are needed. Do not hand-edit
generated parser tables, the generated C interface, or generated Swift catalog.
Edit `LanguagePack.json` and run `make vendor-languages` instead.
