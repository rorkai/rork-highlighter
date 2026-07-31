# ``RorkHighlighter``

Highlight source code with Tree-sitter through a focused Swift API.

## Overview

Create ``Highlighter`` when source text is immutable or changes infrequently.
Open ``HighlightSession`` when an editor needs to preserve its syntax tree
across text edits.

The library exposes capture scopes and UTF-16 ranges without imposing a theme
or rendering framework. This keeps the parser useful to SwiftUI, TextKit,
terminal, and server clients.

## Topics

### Essentials

- <doc:GettingStarted>
- ``Highlighter``
- ``HighlightSnapshot``
- ``HighlightSpan``

### Incremental documents

- <doc:IncrementalHighlighting>
- ``HighlightSession``
- ``HighlightUpdate``
- ``UTF16Range``

### Languages

- <doc:BundledLanguages>
- <doc:RegisteringLanguages>
- ``LanguageCatalog``
- ``HighlightLanguage``
- ``LanguageID``
- ``LanguageQueryKind``

### Configuration and errors

- ``HighlighterConfiguration``
- ``HighlighterError``
