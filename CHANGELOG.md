# Changelog

This document records the user-visible changes in each Rork Highlighter
release.

## Unreleased

### Added

- Added public-workflow performance benchmarks for parsing, incremental edits,
  injections, theme resolution, and native attributed rendering.
- Added clean-build and distribution-size measurement for generated parser
  sources, compiled objects, linked code, and query resources.

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
