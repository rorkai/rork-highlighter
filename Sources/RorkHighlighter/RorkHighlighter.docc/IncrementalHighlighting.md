# Incremental Highlighting

Preserve Tree-sitter state across document edits.

## Open a session

Create one session for each changing document:

```swift
let session = try highlighter.makeSession(source, as: .json)
```

The session is an actor. It serializes parser mutations and can safely receive
edits from independent tasks.

## Apply an edit

Editor ranges use UTF-16 offsets:

```swift
let update = try await session.replaceCharacters(
    in: UTF16Range(location: 10, length: 1),
    with: #""updated""#
)
```

``HighlightUpdate/snapshot`` contains the complete new state.
``HighlightUpdate/invalidatedRanges`` identifies regions whose syntax or
highlighting may have changed.

``HighlightUpdate/rangesRequiringRendering`` combines the replacement with
those invalidation ranges and returns sorted, merged regions in the new
document. Incremental ``HighlightRenderer`` implementations can use that value
without reproducing Tree-sitter-specific range handling.

The session retains captures outside Tree-sitter's invalidated region. It
rebases captures after the edit and queries only the changed syntax before
assembling the complete snapshot. Consumers therefore keep the simple complete
snapshot contract without paying for another full-document query after every
edit.

The session rejects ranges outside the current revision and ranges that split a
Unicode scalar. Read ``HighlightSession/currentRevision`` when coordinating
edits from a versioned text buffer.

## Render TextKit updates

``TextKitHighlightRenderer`` is the built-in backend for UIKit and AppKit. It
applies the session's rendering ranges directly to existing attributed storage:

```swift
let renderer = TextKitHighlightRenderer(theme: .rorkDark)
#if canImport(AppKit)
guard let textStorage = textView.textStorage else {
    return
}
#else
let textStorage = textView.textStorage
#endif
let snapshot = try await session.snapshot()
try renderer.render(snapshot, in: textStorage)

let range = UTF16Range(location: 10, length: 1)
let replacement = "updated"
textStorage.replaceCharacters(
    in: NSRange(location: range.location, length: range.length),
    with: replacement
)
let update = try await session.replaceCharacters(
    in: range,
    with: replacement
)
try renderer.render(update, in: textStorage)
```

``TextKitHighlightRenderer`` retains native style and font caches across
updates. It preserves non-syntax attributes and restyles only the replacement
and ``HighlightUpdate/invalidatedRanges``. Apply each matching TextKit edit and
session update in revision order so the renderer can remain on its incremental
path.
