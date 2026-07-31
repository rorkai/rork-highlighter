# Rendering Attributed Code

Create native attributed output for SwiftUI, UIKit, and AppKit.

## Render a snapshot

Highlight source text, select a theme, and render the immutable snapshot:

```swift
import RorkHighlighter
import SwiftUI

let source = #"""
import SwiftUI

struct WelcomeView: View {
    let name: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
            Text("Hello, \(name)!")
                .font(.title.bold())
        }
    }
}
"""#

let highlighter = try Highlighter()
let snapshot = try highlighter.highlight(source, as: .swift)
let rendered = try snapshot.attributedString(
    theme: .rorkDark,
    font: .system(size: 15, design: .monospaced)
)

let code = Text(rendered)
    .textSelection(.enabled)
```

The syntax colors below come directly from `.rorkDark`. The surrounding editor
chrome is illustrative.

![Swift source highlighted with the Rork Dark theme.](swift-attributed-output.png)

The default font is the monospaced system body font. Pass a font when an editor
or design system owns the typography:

```swift
let rendered = try snapshot.attributedString(
    theme: .rorkLight,
    font: .system(size: 15, design: .monospaced)
)
```

Bold and italic traits derive from the supplied font. Underline and
strikethrough traits become native `AttributedString` line styles. Existing
traits in the caller-provided font remain part of the rendering baseline.

## Render with TextKit

UIKit and AppKit clients can request an `NSAttributedString`:

```swift
let rendered = try snapshot.nsAttributedString(
    theme: .rorkDark,
    font: .monospacedSystemFont(ofSize: 15, weight: .regular)
)
```

The font parameter is a `UIFont` on UIKit platforms and an `NSFont` on AppKit.
The renderer uses the platform's monospaced system font when the parameter is
omitted.

Colors become `UIColor` or `NSColor` values in the sRGB color space. Typography
uses the standard `.font`, `.underlineStyle`, and `.strikethroughStyle` keys, so
the result can be assigned directly to `UILabel`, `UITextView`, `NSTextView`,
and `NSTextStorage` APIs.

## Preserve capture precedence

The renderer applies ``HighlightSnapshot/highlights`` in their stored order.
Later captures can refine colors or replace typography applied by an earlier
overlapping capture. An explicitly empty ``HighlightStyle/textTraits`` set
removes traits inherited from broader theme rules while preserving the
caller-provided base font.

The renderer resolves shared UTF-16 boundaries during one forward traversal of
the source. It does not rescan the complete document for each capture.

## Handle invalid ranges

Rendering throws ``HighlightRenderingError`` when a manually constructed
snapshot contains an out-of-bounds range or a boundary inside a Swift
character. Ranges are never rounded because rounding could color source text
outside the Tree-sitter capture.

The Swift value renderer is available when SwiftUI is present. The TextKit
renderer is available when UIKit or AppKit is present. The raw
``HighlightSnapshot`` and renderer-neutral theme APIs remain available on
other platforms.
