# Changelog

This document records the user-visible changes in each Rork Highlighter
release.

## Unreleased

### Fixed

- Hand-built snapshot boundaries now keep valid scalar positions inside
  grapheme clusters, such as the position before a combining mark. The
  previous alignment used grapheme boundaries and rounded those positions
  down unnecessarily.

## 0.4.0 - 2026-08-24

### Added

- Added `HighlightSnapshot.stableUTF16Length`, which reports how much of the
  leading source parses without end-of-input recovery. Streaming clients can
  render exact captures before the boundary and keep the speculative tail
  neutral until it settles.

### Fixed

- Session captures now always match a one-shot highlight of the same text.
  The bounded incremental query missed patterns that match or stop matching
  nodes whose own structure never changed, which let stale classifications
  survive appends.
- Session invalidation ranges now cover every capture difference between two
  revisions, so incremental renderers no longer leave stale styles outside
  Tree-sitter's structural change ranges.

## 0.3.0 - 2026-08-07

### Added

- Added a framework-agnostic renderer contract for complete snapshots and
  incremental updates with typed backend targets and failures.
- Added named `StyledHighlight` values and snapshot-level theme resolution for
  custom rendering backends.
- Added reusable TextKit rendering that applies incremental invalidation ranges
  to existing `NSTextStorage` while preserving paragraph and custom attributes.
- Added a typed `TextKitRenderingError` contract for invalid snapshots and
  mismatched storage.
- Added separate guides for low-level rendering, native attributed output, and
  editable TextKit integration.

## 0.2.1 - 2026-08-03

### Added

- Added public-workflow performance benchmarks for parsing, incremental edits,
  injections, theme resolution, and native attributed rendering.
- Added opt-in same-corpus comparisons with HighlightKit, swift-highlight, and
  highlight.js.
- Added clean-build and distribution-size measurement for generated parser
  sources, compiled objects, linked code, and query resources.

### Changed

- Incremental sessions now retain unaffected captures and query only
  Tree-sitter's invalidated syntax region while preserving complete snapshots.
- One-shot highlighting now skips nested-language traversal when bundled
  metadata proves no injection can match. It consumes lightweight
  predicate-aware captures with cached names and avoids unnecessary
  whole-result sorting.
- Native attributed rendering now reuses resolved styles, colors, and font
  faces and recognizes parser-produced ranges.

## 0.2.0 - 2026-07-31

### Added

- Added renderer-neutral light and dark themes with hierarchical Tree-sitter
  capture matching.
- Added native SwiftUI `AttributedString` and TextKit `NSAttributedString`
  rendering with caller-selected fonts, typed range errors, and Unicode-safe
  UTF-16 conversion.

### Changed

- Built-in themes now leave attributed text backgrounds unset so the
  surrounding editor or view controls its canvas.
- The Rork Dark numeric-literal color now uses a quieter gold that sits
  naturally beside the surrounding syntax.

## 0.1.0 - 2026-07-31

### Added

- Added one-shot syntax highlighting backed by Tree-sitter.
- Added actor-isolated incremental highlighting sessions with UTF-16 edits and
  invalidation ranges.
- Added a bundled catalog of 36 languages for mobile and web development,
  including nested-language injections.
- Added typed `HighlighterError` contracts for highlighting operations.
- Added deterministic language discovery through identifiers, aliases,
  filenames, and file extensions.
- Added reproducible parser vendoring with pinned revisions, locked file
  hashes, audited licenses, and retained third-party notices.
- Added Swift 6 concurrency checking, complete maintained-code documentation,
  cross-platform tests, and iOS build validation.
