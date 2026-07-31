# Contributing

Thank you for improving Rork Highlighter.

## Design expectations

Follow the Swift API Design Guidelines and preserve source compatibility unless
a release plan explicitly allows a breaking change. Prefer concrete value types
at public boundaries and keep mutable parser state inside an actor.

Every maintained Swift declaration requires a DocC comment, including private
and internal declarations. The comment should explain purpose, ownership, units,
or a non-obvious constraint. It should not restate the declaration.

Every declaration in an authored C header requires consecutive `///` lines.
Generated parser sources and their support headers remain byte-for-byte
upstream files and are exempt from project documentation rules.

Documentation uses complete prose. Avoid label-and-fragment colon patterns,
semicolon-joined clauses, and em dashes.

## Language changes

A parser and its queries must use compatible pinned upstream revisions. Before
adding a grammar, verify its parser ABI, compile every query, run a
representative highlight fixture, and audit the license of every distributed
file.

Official packs accept only permissive licenses suitable for Apache-2.0
distribution. Update `THIRD_PARTY_NOTICES.md` whenever bundled third-party
content changes.

Edit `LanguagePack.json` when changing the common pack, then regenerate all
managed files:

```bash
make vendor-languages
```

The generated lock stores a SHA-256 digest for every parser, support header,
query, license, and generated interface. `make check` verifies those bytes
without accessing the network.

## Validation

Run the full validation before opening a pull request:

```bash
make check
```

Use the formatter when lint reports style differences:

```bash
make format
```

Generated parser tables are reviewed through their pinned upstream revision and
generation metadata. Do not hand-edit them.
