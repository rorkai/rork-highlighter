# Roadmap

The roadmap grows the language catalog and rendering layer without weakening
the initial API and correctness guarantees.

## Foundation

- Keep the Swift 6 package, one-shot API, incremental actor session, and common
  language fixtures green on macOS, iOS, and Linux.
- Preserve complete DocC coverage for maintained declarations.
- Maintain public-workflow benchmarks for catalog initialization, one-shot
  highlighting, incremental edits, injections, theme resolution, and native
  rendering.

## Rendering

- Keep hierarchical theme resolution independent of any rendering framework.
- Keep the generic renderer contract independent of storage, layout, and
  drawing technology.
- Provide native `AttributedString` and `NSAttributedString` output on Apple
  platforms as optional conveniences.
- Keep incremental TextKit rendering aligned with session invalidation ranges
  as one concrete backend without rebuilding an entire attributed document.
- Keep raw highlight spans available for custom editors and servers.

## Common languages

- Track clean source-build time and source, object, linked executable, and
  resource sizes for the current 36 definitions.
- Keep the mobile and web set focused on formats with demonstrated demand.
- Extend injection coverage when a compatible parser and permissive query
  source can be pinned together.

## Pack tooling

- Keep the common parser pack source-based and track its consumer build cost.
- Revisit precompiled delivery only when repeatable consumer benchmarks justify
  its download footprint and release complexity.
- Keep the common pack's measured consumer footprint visible in public
  documentation.
- Revisit selectable packs only when measured size or demonstrated consumer
  demand justifies the additional package and maintenance complexity.
