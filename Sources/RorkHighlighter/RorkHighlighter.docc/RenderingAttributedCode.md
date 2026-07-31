# Rendering Attributed Code

Create a native `AttributedString` for SwiftUI on Apple platforms.

## Render a snapshot

Highlight source text, select a theme, and render the immutable snapshot:

```swift
import RorkHighlighter
import SwiftUI

let highlighter = try Highlighter()
let snapshot = try highlighter.highlight(
    #"let greeting = "Hello""#,
    as: .swift
)
let rendered = try snapshot.attributedString(theme: .rorkDark)

let code = Text(rendered)
```

The default font is the monospaced system body font. Pass a font when an editor
or design system owns the typography:

```swift
let rendered = try snapshot.attributedString(
    theme: .rorkLight,
    font: .system(size: 15, design: .monospaced)
)
```

Bold and italic traits derive from the supplied font. Underline and
strikethrough traits become native `AttributedString` line styles.

## Preserve capture precedence

The renderer applies ``HighlightSnapshot/highlights`` in their stored order.
Later captures can refine colors or replace typography applied by an earlier
overlapping capture. An explicitly empty ``HighlightStyle/textTraits`` set
removes inherited text traits.

The renderer resolves shared UTF-16 boundaries during one forward traversal of
the source. It does not rescan the complete document for each capture.

## Handle invalid ranges

Rendering throws ``HighlightRenderingError`` when a manually constructed
snapshot contains an out-of-bounds range or a boundary inside a Swift
character. Ranges are never rounded because rounding could color source text
outside the Tree-sitter capture.

The attributed renderer is available when SwiftUI is present. The raw
``HighlightSnapshot`` and renderer-neutral theme APIs remain available on
non-Apple platforms.
