# ``RorkHighlighter``

Highlight source code with Tree-sitter through a focused Swift API.

## Overview

Create ``Highlighter`` when source text is immutable or changes infrequently.
Open ``HighlightSession`` when an editor needs to preserve its syntax tree
across text edits.

The library exposes capture scopes and UTF-16 ranges together with
renderer-neutral themes. These values form the framework-agnostic core.
``HighlightRenderer`` adds an extensible contract for applying complete
snapshots and incremental updates to any backend.

Apple integrations remain separate conveniences. Complete snapshots can become
native attributed values, while ``TextKitHighlightRenderer`` can update
existing UIKit or AppKit storage incrementally.

## Topics

### Essentials

- <doc:GettingStarted>
- ``Highlighter``
- ``HighlightSnapshot``
- ``HighlightSpan``

### Framework-agnostic styling and rendering

- <doc:Theming>
- <doc:RenderingBackends>
- ``HighlightTheme``
- ``HighlightStyle``
- ``StyledHighlight``
- ``HighlightColor``
- ``HighlightTextTrait``
- ``HighlightRenderer``

### Incremental documents

- <doc:IncrementalHighlighting>
- ``HighlightSession``
- ``HighlightUpdate``
- ``UTF16Range``

### Apple rendering

- <doc:RenderingAttributedCode>
- <doc:TextKitIntegration>
- ``TextKitHighlightRenderer``
- ``TextKitRenderingError``
- ``HighlightRenderingError``

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
