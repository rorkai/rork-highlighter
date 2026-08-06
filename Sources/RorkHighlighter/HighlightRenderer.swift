/// Renders complete and incremental highlighting state into a backend target.
///
/// Renderers own backend-specific configuration and caching. The target can be
/// native text storage, a graphics surface, a terminal buffer, or another
/// destination that understands highlighted source text.
///
/// The protocol does not prescribe layout, drawing, or attribute semantics.
/// Implementations interpret renderer-neutral snapshots, themes, and ranges
/// according to their backend.
public protocol HighlightRenderer<Target, Failure> {
    /// Names the destination that receives rendered highlighting state.
    associatedtype Target

    /// Names the failures emitted by the rendering backend.
    associatedtype Failure: Error

    /// Renders a complete highlighting snapshot into a target.
    ///
    /// - Parameters:
    ///   - snapshot: The complete highlighting state to render.
    ///   - target: The backend destination receiving the state.
    /// - Throws: `Failure` when the backend cannot render the snapshot.
    mutating func render(
        _ snapshot: HighlightSnapshot,
        in target: Target
    ) throws(Failure)

    /// Renders an incremental highlighting update into a target.
    ///
    /// Implementations can use ``HighlightUpdate/renderingRanges`` to limit
    /// work to the affected regions. Renderers without an incremental path
    /// receive a default implementation that renders the complete latest
    /// snapshot.
    ///
    /// - Parameters:
    ///   - update: The incremental highlighting state to render.
    ///   - target: The backend destination receiving the state.
    /// - Throws: `Failure` when the backend cannot render the update.
    mutating func render(
        _ update: HighlightUpdate,
        in target: Target
    ) throws(Failure)
}

/// Supplies complete-snapshot fallback behavior for rendering backends.
public extension HighlightRenderer {
    /// Renders the latest complete snapshot when no incremental path exists.
    ///
    /// - Parameters:
    ///   - update: The update containing the latest complete snapshot.
    ///   - target: The backend destination receiving the snapshot.
    /// - Throws: `Failure` when the backend cannot render the snapshot.
    mutating func render(
        _ update: HighlightUpdate,
        in target: Target
    ) throws(Failure) {
        try render(update.snapshot, in: target)
    }
}
