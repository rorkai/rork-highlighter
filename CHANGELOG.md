# Changelog

This document records the user-visible changes in each Rork Highlighter
release.

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
