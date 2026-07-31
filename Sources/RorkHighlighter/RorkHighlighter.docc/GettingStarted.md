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
let snapshot = try highlighter.highlight(
    #"let greeting = "Hello""#,
    as: .swift
)
```

Use a file URL when its filename or extension should choose the language:

```swift
let snapshot = try highlighter.highlight(
    source,
    for: URL(fileURLWithPath: "/tmp/settings.json")
)
```

Each ``HighlightSpan`` contains a Tree-sitter capture scope and a
``UTF16Range``. Spans can overlap because a specific capture may refine a
broader one. Apply spans in their returned order when resolving theme
precedence.
