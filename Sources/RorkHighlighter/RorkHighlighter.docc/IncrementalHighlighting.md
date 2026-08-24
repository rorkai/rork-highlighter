# Incremental Highlighting

Preserve Tree-sitter state across document edits.

## Open a session

Create one session for each changing document:

```swift
import RorkHighlighter

let highlighter = try Highlighter()
let source = #"{"name":"Rork"}"#
let session = try highlighter.makeSession(source, as: .json)
```

The session is an actor. It serializes parser mutations and can safely receive
edits from independent tasks.

## Apply an edit

Editor ranges use UTF-16 offsets:

```swift
let update = try await session.replaceCharacters(
    in: UTF16Range(location: 9, length: 4),
    with: "Codex"
)
```

``HighlightUpdate/snapshot`` contains the complete new state.
``HighlightUpdate/invalidatedRanges`` identifies regions whose syntax or
highlighting may have changed.

``HighlightUpdate/renderingRanges`` combines the replacement with those
invalidation ranges and returns sorted, merged regions in the new document.
Incremental ``HighlightRenderer`` implementations can use that value without
reproducing Tree-sitter-specific range handling.

The session reuses the edited syntax tree, so parsing stays incremental, and
it queries the complete document so its captures always match a one-shot
highlight of the same tree. A query pattern can match or stop matching a node
whose own structure never changed, for example a name that becomes a call
once its argument list appears. The invalidation ranges therefore cover every
capture difference between the two revisions, not only the structural edit.

The session rejects ranges outside the current revision and ranges that split a
Unicode scalar. Read ``HighlightSession/currentRevision`` when coordinating
edits from a versioned text buffer.

## Track stability while streaming

Streamed documents usually end in the middle of a token or construct, and
Tree-sitter classifies that tail through error recovery.
``HighlightSnapshot/stableUTF16Length`` reports how much of the leading
source parses without end-of-input recovery. Captures that end before the
boundary match a one-shot highlight of the same text and rarely change when
more source is appended, while captures at or beyond it can still be
reinterpreted by the next chunk.

Streaming clients can render exact captures before the boundary and keep the
speculative tail neutral until it settles. The boundary is derived from the
parsed syntax trees, including injected languages, so an open Markdown fence
still reports fine-grained stability for the embedded code it contains.

## Choose a rendering path

Incremental highlighting does not depend on a presentation framework. A custom
pipeline can consume ``HighlightUpdate/snapshot`` and refresh
``HighlightUpdate/renderingRanges`` directly. Implement ``HighlightRenderer``
when that behavior should become a reusable backend.

Read <doc:RenderingBackends> for the low-level renderer contract. Read
<doc:TextKitIntegration> when an editable UIKit or AppKit view owns the
destination storage.
