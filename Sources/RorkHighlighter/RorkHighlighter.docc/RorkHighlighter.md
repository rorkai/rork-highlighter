# ``RorkHighlighter``

Highlight source code with Tree-sitter through a focused Swift API.

## Overview

Create ``Highlighter`` when source text is immutable or changes infrequently.
Open ``HighlightSession`` when an editor needs to preserve its syntax tree
across text edits.

The library exposes capture scopes and UTF-16 ranges together with
renderer-neutral themes. Apple clients can render snapshots into native
`AttributedString` or `NSAttributedString` values. Raw spans remain available
to custom editors, terminal clients, and servers that need complete control.

## Topics

### Essentials

- <doc:GettingStarted>
- ``Highlighter``
- ``HighlightSnapshot``
- ``HighlightSpan``

### Themes

- <doc:Theming>
- <doc:RenderingAttributedCode>
- ``HighlightTheme``
- ``HighlightStyle``
- ``HighlightColor``
- ``HighlightTextTrait``
- ``HighlightRenderingError``

### Incremental documents

- <doc:IncrementalHighlighting>
- ``HighlightSession``
- ``HighlightUpdate``
- ``TextKitHighlightRenderer``
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
