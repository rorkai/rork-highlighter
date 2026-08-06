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
    .padding()
    .background(Color.black)
```

The syntax colors below come directly from `.rorkDark`. The surrounding editor
chrome is illustrative.

![Swift source highlighted with the Rork Dark theme.](swift-attributed-output.png)

The bundled themes leave ``HighlightStyle/backgroundColor`` unset. Set the
canvas on the containing view or editor so attributed text does not paint
background strips behind individual text runs.

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

## Update TextKit storage incrementally

``TextKitHighlightRenderer`` is the built-in ``HighlightRenderer`` backend for
the `NSTextStorage` shared by TextKit 1 and TextKit 2. Create one renderer
beside each changing storage instance. The storage must contain the source
represented by the first snapshot:

```swift
let session = try highlighter.makeSession(source, as: .swift)
let renderer = TextKitHighlightRenderer(
    theme: .rorkDark,
    font: .monospacedSystemFont(ofSize: 15, weight: .regular)
)
#if canImport(AppKit)
guard let textStorage = textView.textStorage else {
    return
}
#else
let textStorage = textView.textStorage
#endif
let snapshot = try await session.snapshot()
try renderer.render(snapshot, in: textStorage)
```

Apply each character edit to TextKit and the highlighting session before
rendering the returned update:

```swift
let editRange = UTF16Range(location: 24, length: 4)
let replacement = "2000"

textStorage.replaceCharacters(
    in: NSRange(location: editRange.location, length: editRange.length),
    with: replacement
)
let update = try await session.replaceCharacters(
    in: editRange,
    with: replacement
)
try renderer.render(update, in: textStorage)
```

The renderer resets and reapplies only syntax-owned font, foreground,
background, underline, and strikethrough values inside the replacement and
invalidated ranges. Paragraph styles, links, attachments, and custom attributes
remain untouched.

Apply updates in document revision order. The incremental path deliberately
does not compare the complete source string after each edit. A skipped revision,
another storage instance, or an incompatible length triggers a verified complete
render. A same-length out-of-order edit remains the caller's responsibility to
reject through its document revision.

Changing ``TextKitHighlightRenderer/theme`` or its platform font clears cached
document state. Render the current complete snapshot after changing appearance,
or pass the next update when the storage already contains that snapshot source.

## Preserve capture precedence

The renderer applies ``HighlightSnapshot/highlights`` in their stored order.
Later captures can refine colors or replace typography applied by an earlier
overlapping capture. An explicitly empty ``HighlightStyle/textTraits`` set
removes traits inherited from broader theme rules while preserving the
caller-provided base font.

The renderer resolves shared UTF-16 boundaries during one forward traversal of
the source. It does not rescan the complete document for each capture. Styles,
native colors, and derived font faces are reused when capture scopes repeat.

## Handle invalid ranges

Rendering throws ``HighlightRenderingError`` when a manually constructed
snapshot contains an out-of-bounds range or a boundary inside a Swift
character. Ranges are never rounded because rounding could color source text
outside the Tree-sitter capture.

Snapshots produced by ``Highlighter`` and ``HighlightSession`` carry
Tree-sitter range provenance. The TextKit renderer recognizes that provenance
and avoids repeating the Unicode boundary validation pass.

The Swift value renderer is available when SwiftUI is present. The TextKit
renderer is available when UIKit or AppKit is present. The raw
``HighlightSnapshot`` and renderer-neutral theme APIs remain available on
other platforms.
