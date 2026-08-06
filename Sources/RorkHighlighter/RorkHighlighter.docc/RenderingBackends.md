# Building Rendering Backends

Connect renderer-neutral highlighting state to graphics APIs, terminals, or
custom display systems.

This article covers the low-level, framework-agnostic rendering contract. It
does not require SwiftUI, UIKit, AppKit, or TextKit.

## Understand the contract

``HighlightRenderer`` separates parsed highlighting state from its final
presentation. Each implementation selects a target and typed failure while the
highlighter supplies the same renderer-neutral values:

- ``HighlightSnapshot`` contains the complete source, revision, language, and
  ordered capture spans.
- ``HighlightUpdate`` contains the latest complete snapshot and the ranges
  affected by an edit.
- ``HighlightTheme`` resolves each capture span into a platform-neutral style.

The protocol does not prescribe drawing commands, layout, font objects, or
storage ownership. A Metal backend can encode GPU data, a terminal backend can
emit escape sequences, and a text-system backend can apply native attributes.

## Implement complete rendering

A backend only needs to implement complete snapshot rendering. The default
update implementation renders the latest complete snapshot, which gives every
renderer correct behavior before it adds an optimized incremental path.

```swift
import RorkHighlighter

/// Stores styles understood by an application-specific display surface.
final class CodeSurface {
    /// Holds the source currently represented by the surface.
    var text: String

    /// Holds ordered styles resolved for the current source.
    var styles: [(range: UTF16Range, style: HighlightStyle)] = []

    /// Creates a surface for source that has not been styled yet.
    ///
    /// - Parameter text: The initial source shown by the surface.
    init(text: String) {
        self.text = text
    }
}

/// Reports failures from the application-specific display surface.
enum CodeSurfaceError: Error {
    /// The surface and snapshot represent different source text.
    case sourceMismatch
}

/// Applies renderer-neutral styles to an application-specific surface.
struct CodeSurfaceRenderer: HighlightRenderer {
    /// Uses the application's display surface as the target.
    typealias Target = CodeSurface

    /// Reports failures through the surface's error type.
    typealias Failure = CodeSurfaceError

    /// Resolves capture scopes through this theme.
    var theme: HighlightTheme

    /// Applies every ordered capture from a complete snapshot.
    ///
    /// - Parameters:
    ///   - snapshot: The complete highlighting state to render.
    ///   - target: The display surface receiving resolved styles.
    /// - Throws: `CodeSurfaceError.sourceMismatch` when the source differs.
    mutating func render(
        _ snapshot: HighlightSnapshot,
        in target: CodeSurface
    ) throws(CodeSurfaceError) {
        guard target.text == snapshot.text else {
            throw .sourceMismatch
        }
        target.styles = snapshot.highlights.map { span in
            (span.range, theme.style(for: span))
        }
    }
}
```

Capture order is significant because later overlapping spans can refine styles
applied by earlier spans. A backend can preserve the ordered operations shown
above or flatten them into its own nonoverlapping representation.

## Add incremental rendering

Implement the update overload when the target can replace styling in only part
of a document. ``HighlightUpdate/rangesRequiringRendering`` combines the
replacement range with Tree-sitter's invalidation ranges, removes empty ranges,
and merges adjacent or overlapping regions.

The latest complete spans remain available through
``HighlightUpdate/snapshot``. An incremental backend clears its owned styling
inside the rendering ranges and reapplies intersecting spans in their stored
order. The backend remains responsible for applying the same character edit to
its text model before rendering the matching update.

## Choose an Apple integration

Read <doc:RenderingAttributedCode> when a complete native attributed value is
enough. Read <doc:TextKitIntegration> when an editable UIKit or AppKit view
owns the destination storage.
