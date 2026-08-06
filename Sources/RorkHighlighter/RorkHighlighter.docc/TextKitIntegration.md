# Integrating with TextKit

Apply complete snapshots and incremental updates to UIKit or AppKit text
storage.

## Understand the integration

``TextKitHighlightRenderer`` is an optional rendering backend. It accepts
the `NSTextStorage` exposed by TextKit 1 and TextKit 2, but it does not own a
text view, layout manager, selection, scrolling, or editing behavior.

Use this integration when an editable UIKit or AppKit view already owns its
attributed storage. Use <doc:RenderingAttributedCode> when a complete
`AttributedString` or `NSAttributedString` is enough. Use
<doc:RenderingBackends> when another rendering system owns the output.

The renderer retains mutable caches and is not `Sendable`. Keep one renderer
with each storage instance and use it on the same isolation domain that owns
that storage.

## Render UIKit storage

Place the snapshot source into the text view before rendering:

```swift
import RorkHighlighter
import UIKit

let snapshot = try Highlighter().highlight(source, as: .swift)
textView.text = snapshot.text

let renderer = TextKitHighlightRenderer(theme: .rorkDark)
try renderer.render(snapshot, in: textView.textStorage)
```

The default font is UIKit's monospaced system body font. Pass another base font
when the surrounding interface owns typography:

```swift
let renderer = TextKitHighlightRenderer(
    theme: .rorkDark,
    font: .monospacedSystemFont(ofSize: 15, weight: .regular)
)
```

## Render AppKit storage

`NSTextView.textStorage` is optional on AppKit, so unwrap the storage before
rendering:

```swift
import AppKit
import RorkHighlighter

let snapshot = try Highlighter().highlight(source, as: .swift)
textView.string = snapshot.text

guard let textStorage = textView.textStorage else {
    return
}

let renderer = TextKitHighlightRenderer(theme: .rorkDark)
try renderer.render(snapshot, in: textStorage)
```

Pass an `NSFont` to the same initializer when the default monospaced system
font is not appropriate.

## Render document edits

Create one ``HighlightSession`` and one renderer for the editable document.
The initial complete render establishes the storage identity, source length,
language, and revision used by the incremental path:

```swift
let session = try highlighter.makeSession(source, as: .swift)
let renderer = TextKitHighlightRenderer(theme: .rorkDark)

let snapshot = try await session.snapshot()
try renderer.render(snapshot, in: textStorage)
```

Ask the session to validate and apply each edit first. This keeps TextKit
unchanged when the session rejects a range. Apply the same replacement to
TextKit after the session succeeds, then render the matching update:

```swift
let range = UTF16Range(location: 24, length: 4)
let replacement = "Rork"

let update = try await session.replaceCharacters(
    in: range,
    with: replacement
)

textStorage.replaceCharacters(
    in: NSRange(location: range.location, length: range.length),
    with: replacement
)

try renderer.render(update, in: textStorage)
```

The renderer clears and reapplies syntax-owned attributes only inside
``HighlightUpdate/rangesRequiringRendering``. That value combines the
replacement with Tree-sitter invalidation ranges and merges adjacent or
overlapping regions.

## Keep storage and session synchronized

Apply updates in document revision order. The incremental path checks storage
identity, document length, language, revision, and edit metadata without
comparing the complete source after every keystroke.

A skipped revision, another storage instance, or incompatible edit metadata
causes a verified complete render. That fallback succeeds when the storage
already contains ``HighlightUpdate/snapshot`` text. It throws
``HighlightRenderingError/textStorageMismatch(snapshotRevision:expectedLength:actualLength:)``
when the source differs.

Reject same-length out-of-order edits in the document model before sending them
to the renderer because length alone cannot reveal that ordering mistake.

## Preserve application attributes

The renderer owns the following attributes:

- Font.
- Foreground and background color.
- Underline.
- Strikethrough.

It leaves paragraph styles, links, attachments, and custom attributes
untouched. The bundled themes also leave text backgrounds unset, so the text
view remains responsible for its canvas color.

## Change appearance

Assigning another ``TextKitHighlightRenderer/theme`` or platform font clears
the cached document state. Render the current complete snapshot after changing
appearance. Passing the next update also works when the storage already
contains that update's complete snapshot source because the renderer can
resynchronize through its verified fallback.

## Handle range failures

The renderer throws ``HighlightRenderingError`` for storage mismatches,
out-of-bounds spans, and UTF-16 ranges that split a Swift character. It never
rounds invalid ranges because doing so could style text outside the original
Tree-sitter capture.
