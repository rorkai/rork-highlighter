# Changelog

This document records the user-visible changes in each Rork Highlighter
release.

## Unreleased

### Added

- Added a reproducible static parser XCFramework pipeline with primary Apple
  platform coverage, deterministic archives, SwiftPM checksums, retained
  licenses, exported-symbol validation, and a real binary-consumer smoke test.
- Added destination builds that verify binary delivery and source fallbacks
  across every supported Apple platform.

### Changed

- iOS, macOS, and Mac Catalyst builds now consume a 26.3 MB common parser
  archive without changing the package product or Swift import. Its extracted
  footprint is about 273 MiB instead of 624 MiB.
- tvOS, watchOS, visionOS, and non-Apple builds continue to compile the locked
  parser sources.

### Fixed

- Fixed the default UIKit rendering font on tvOS and watchOS by deriving its
  size from the preferred body font.

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
