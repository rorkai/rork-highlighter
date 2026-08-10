# Theming

Resolve Tree-sitter capture scopes into renderer-neutral visual styles.

## Use a bundled theme

Rork Highlighter includes light and dark themes. Both themes are immutable,
`Sendable`, and `Codable`:

```swift
let highlighter = try Highlighter()
let snapshot = try highlighter.highlight(
    #"let greeting = "Hello""#,
    as: .swift
)
let styledHighlights = snapshot.styledHighlights(using: .rorkDark)

for highlight in styledHighlights {
    print(highlight.span.scope, highlight.style)
}
```

``HighlightSnapshot/styledHighlights(using:)`` returns named
``StyledHighlight`` values in capture order. The base style supplies defaults
for rendered text. The bundled themes leave their text background unset so the
surrounding editor or view controls its canvas. Each highlighted span receives
the base style followed by every matching scope refinement.

## Define a custom theme

Create a ``HighlightTheme`` from a base ``HighlightStyle`` and a dictionary of
dotted capture scopes:

```swift
let theme = HighlightTheme(
    name: "Brand",
    baseStyle: HighlightStyle(
        foregroundColor: HighlightColor(rgb: 0xE6E6E6),
        textTraits: []
    ),
    styles: [
        "comment": HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x7A8A99),
            textTraits: [.italic]
        ),
        "keyword": HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xD99BFF)
        ),
    ]
)
```

Colors use eight-bit sRGB channels and remain independent of UIKit, AppKit, and
SwiftUI. Text traits describe bold, italic, underline, and strikethrough
presentation without selecting a platform font.

``HighlightStyle/backgroundColor`` paints only the attributed text range. Set
the editor canvas on the containing SwiftUI view, `UITextView`, or `NSTextView`.

Integer literals passed to ``HighlightColor/init(rgb:alpha:)`` are checked as
24-bit values. Validate colors obtained from files or network responses with
``HighlightColor/RGB/init(rawValue:)`` before constructing a color.

## Refine hierarchical scopes

Tree-sitter capture names become more specific from left to right. Resolving
`string.special.key` applies the `string`, `string.special`, and
`string.special.key` rules in that order.

A missing style value preserves the broader value. An empty
``HighlightStyle/textTraits`` set removes traits inherited from broader theme
rules:

```swift
let theme = HighlightTheme(
    name: "Markup",
    styles: [
        "markup": HighlightStyle(textTraits: [.italic]),
        "markup.raw": HighlightStyle(textTraits: []),
    ]
)
```

Unknown and malformed capture scopes receive the theme's base style. Matching
is case-sensitive because Tree-sitter capture names are case-sensitive.
