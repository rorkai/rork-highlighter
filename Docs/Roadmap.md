# Roadmap

The roadmap grows the language catalog and rendering layer without weakening
the initial API and correctness guarantees.

## Foundation

- Keep the Swift 6 package, one-shot API, incremental actor session, and common
  language fixtures green on macOS, iOS, and Linux.
- Preserve complete DocC coverage for maintained declarations.
- Add benchmarks for parse, edit, query, and snapshot conversion costs.

## Rendering

- Keep hierarchical theme resolution independent of any rendering framework.
- Provide native `AttributedString` output on Apple platforms.
- Add TextKit adapters that can apply invalidated ranges without rebuilding an
  entire document.
- Keep raw highlight spans available for custom editors and servers.

## Common languages

- Measure source-build time and linked size for the current 36 definitions.
- Keep the mobile and web set focused on formats with demonstrated demand.
- Extend injection coverage when a compatible parser and permissive query
  source can be pinned together.

## Pack tooling

- Generate Apple XCFramework slices for clients that prefer binary parsers.
- Add a tool that builds a custom pack from a selected language list.
- Publish common, domain, and all-language artifacts with measured size data.
