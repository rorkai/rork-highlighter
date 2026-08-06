# Getting Started

Create highlights for an immutable source string.

## Create a highlighter

The default initializer loads the package's bundled language catalog:

```swift
import RorkHighlighter

let highlighter = try Highlighter()
```

The standard catalog includes Bash, C, C++, CSS, Go, HTML, Java, JavaScript,
JSON, Markdown, Markdown Inline, Python, Rust, Swift, TOML, TypeScript, TSX, and
YAML.

## Highlight source text

Select a language explicitly when its identity is already known:

```swift
let source = #"let greeting = "Hello""#
let snapshot = try highlighter.highlight(source, as: .swift)
```

Use a file URL when its filename or extension should choose the language:

```swift
import Foundation
import RorkHighlighter

let source = #"{"name":"Rork"}"#
let snapshot = try Highlighter().highlight(
    source,
    for: URL(fileURLWithPath: "/tmp/settings.json")
)
```

Each ``HighlightSpan`` contains a Tree-sitter capture scope and a
``UTF16Range``. Spans can overlap because a specific capture may refine a
broader one. Apply spans in their returned order when resolving theme
precedence.

## Choose the next layer

The snapshot and theme APIs are framework agnostic. Read <doc:Theming> to
resolve capture scopes yourself or <doc:RenderingBackends> to build a reusable
renderer.

Read <doc:RenderingAttributedCode> for complete SwiftUI, UIKit, or AppKit
output. Read <doc:IncrementalHighlighting> when a document changes over time,
and use <doc:TextKitIntegration> only when an editable Apple text view owns the
destination storage.
