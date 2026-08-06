# Rendering Native Attributed Output

Create complete attributed values for SwiftUI, UIKit, and AppKit.

## Understand native output

Native attributed output is a convenience built on the framework-agnostic
snapshot and theme APIs. It is useful for code blocks, previews, labels, static
text views, and any destination that does not need an incremental rendering
backend.

This API returns a new `AttributedString` or `NSAttributedString`. It does
not own a view or mutate an existing editor. See <doc:TextKitIntegration> when
an editable UIKit or AppKit view already owns its text storage. See
<doc:RenderingBackends> for a non-Apple or custom rendering target.

## Render in SwiftUI

Highlight the source, render its complete snapshot, and pass the native value
to `Text`:

```swift
import RorkHighlighter
import SwiftUI

let source = #"""
import SwiftUI

struct WelcomeView: View {
    let name: String

    var body: some View {
        Text("Hello, \(name)!")
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
    .padding()
```

The syntax colors below come directly from `.rorkDark`. The surrounding
editor chrome is illustrative.

![Swift source highlighted with the Rork Dark theme.](swift-attributed-output.png)

The default font is the monospaced system body font. Pass another SwiftUI font
when the surrounding interface owns typography:

```swift
let rendered = try snapshot.attributedString(
    theme: .rorkLight,
    font: .system(size: 14, design: .monospaced)
)
```

## Render for UIKit

Request an `NSAttributedString` with a `UIFont`:

```swift
import RorkHighlighter
import UIKit

let rendered = try snapshot.nsAttributedString(
    theme: .rorkDark,
    font: .monospacedSystemFont(ofSize: 15, weight: .regular)
)

label.attributedText = rendered
```

The result also works with `UITextView.attributedText` and other UIKit APIs
that accept attributed strings.

## Render for AppKit

The same API accepts an `NSFont` on AppKit:

```swift
import AppKit
import RorkHighlighter

let rendered = try snapshot.nsAttributedString(
    theme: .rorkDark,
    font: .monospacedSystemFont(ofSize: 15, weight: .regular)
)

textView.textStorage?.setAttributedString(rendered)
```

Use <doc:TextKitIntegration> instead when the view is editable and should
retain parser and renderer state between changes.

## Control the canvas

The bundled themes leave ``HighlightStyle/backgroundColor`` unset. Set the
canvas on the containing SwiftUI view, `UIView`, or `NSView` so attributed
runs do not paint separate background strips.

Colors become native sRGB values. Bold and italic traits derive from the
caller-provided base font. Underline and strikethrough traits use the standard
native attributed-string keys.

## Preserve capture precedence

Native rendering applies ``HighlightSnapshot/highlights`` in stored order.
Later captures can refine colors or replace typography from an earlier
overlapping capture. An explicitly empty ``HighlightStyle/textTraits`` set
removes traits inherited from broader theme rules while preserving the base
font supplied by the caller.

## Handle invalid ranges

Rendering throws ``HighlightRenderingError`` when a manually constructed
snapshot contains an out-of-bounds range or a boundary inside a Swift
character. Ranges are never rounded because rounding could color source outside
the Tree-sitter capture.

Snapshots produced by ``Highlighter`` and ``HighlightSession`` carry
validated Tree-sitter range provenance, so native rendering can avoid repeating
the Unicode boundary validation pass.

SwiftUI attributed output is available when SwiftUI is present. Native
`NSAttributedString` output is available when UIKit or AppKit is present. Raw
``HighlightSnapshot`` values and renderer-neutral themes remain available
on other platforms.
