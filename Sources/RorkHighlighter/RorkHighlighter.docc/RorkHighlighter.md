# ``RorkHighlighter``

Highlight source code with Tree-sitter through a focused Swift API.

## Overview

Create ``Highlighter`` when source text is immutable or changes infrequently.
Open ``HighlightSession`` when an editor needs to preserve its syntax tree
across text edits.

The library exposes capture scopes and UTF-16 ranges together with
renderer-neutral themes. Raw spans remain available to SwiftUI, TextKit,
terminal, and server clients that need custom rendering.

## Topics

### Essentials

- <doc:GettingStarted>
- ``Highlighter``
- ``HighlightSnapshot``
- ``HighlightSpan``

### Themes

- <doc:Theming>
- ``HighlightTheme``
- ``HighlightStyle``
- ``HighlightColor``
- ``HighlightTextTrait``

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
