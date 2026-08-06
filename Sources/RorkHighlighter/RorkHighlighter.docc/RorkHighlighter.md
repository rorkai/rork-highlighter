# ``RorkHighlighter``

Highlight source code with Tree-sitter through a focused Swift API.

## Overview

Create ``Highlighter`` when source text is immutable or changes infrequently.
Open ``HighlightSession`` when an editor needs to preserve its syntax tree
across text edits.

The library exposes capture scopes and UTF-16 ranges together with
renderer-neutral themes. ``HighlightRenderer`` defines an extensible contract
for applying complete snapshots and incremental updates to any backend. Apple
clients also receive native attributed output and an optimized TextKit
implementation.

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

### Rendering

- <doc:RenderingBackends>
- <doc:RenderingAttributedCode>
- ``HighlightRenderer``
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
