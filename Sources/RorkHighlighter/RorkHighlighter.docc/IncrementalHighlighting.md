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

The session retains captures outside Tree-sitter's invalidated region. It
rebases captures after the edit and queries only the changed syntax before
assembling the complete snapshot. Consumers therefore keep the simple complete
snapshot contract without paying for another full-document query after every
edit.

The session rejects ranges outside the current revision and ranges that split a
Unicode scalar. Read ``HighlightSession/currentRevision`` when coordinating
edits from a versioned text buffer.

## Render TextKit updates

UIKit and AppKit clients can apply the session's invalidation ranges directly
to existing attributed storage:

```swift
let renderer = TextKitHighlightRenderer(theme: .rorkDark)
let snapshot = try await session.snapshot()
try renderer.render(snapshot, in: textView.textStorage)

let range = UTF16Range(location: 10, length: 1)
let replacement = "updated"
textView.textStorage.replaceCharacters(
    in: NSRange(location: range.location, length: range.length),
    with: replacement
)
let update = try await session.replaceCharacters(
    in: range,
    with: replacement
)
try renderer.render(update, in: textView.textStorage)
```

``TextKitHighlightRenderer`` retains native style and font caches across
updates. It preserves non-syntax attributes and restyles only the replacement
and ``HighlightUpdate/invalidatedRanges``. Apply each matching TextKit edit and
session update in revision order so the renderer can remain on its incremental
path.
