import Testing

@testable import RorkHighlighter

/// Verifies the renderer-neutral backend contract and update ranges.
@Suite
struct HighlightRendererTests {
    /// Records complete and incremental states received by a test backend.
    private final class RecordingTarget {
        /// Stores revisions rendered through the complete path.
        var snapshotRevisions: [UInt64] = []

        /// Stores revisions rendered through the incremental path.
        var updateRevisions: [UInt64] = []
    }

    /// Names the typed failure exposed by test rendering backends.
    enum RecordingError: Error {
        /// Represents a rejected rendering operation.
        case rejected
    }

    /// Records complete snapshots and relies on the default update fallback.
    private struct CompleteSnapshotRenderer: HighlightRenderer {
        /// Uses the reference-backed recording destination.
        typealias Target = RecordingTarget

        /// Exposes the test backend's typed failure contract.
        typealias Failure = RecordingError

        /// Records one complete snapshot revision.
        ///
        /// - Parameters:
        ///   - snapshot: The complete state received by the backend.
        ///   - target: The destination recording the revision.
        /// - Throws: `RecordingError` when the test backend rejects rendering.
        func render(
            _ snapshot: HighlightSnapshot,
            in target: RecordingTarget
        ) throws(RecordingError) {
            target.snapshotRevisions.append(snapshot.revision)
        }
    }

    /// Records complete snapshots and optimized incremental updates separately.
    private struct IncrementalRenderer: HighlightRenderer {
        /// Uses the reference-backed recording destination.
        typealias Target = RecordingTarget

        /// Exposes the test backend's typed failure contract.
        typealias Failure = RecordingError

        /// Records one complete snapshot revision.
        ///
        /// - Parameters:
        ///   - snapshot: The complete state received by the backend.
        ///   - target: The destination recording the revision.
        /// - Throws: `RecordingError` when the test backend rejects rendering.
        func render(
            _ snapshot: HighlightSnapshot,
            in target: RecordingTarget
        ) throws(RecordingError) {
            target.snapshotRevisions.append(snapshot.revision)
        }

        /// Records one incremental update revision.
        ///
        /// - Parameters:
        ///   - update: The incremental state received by the backend.
        ///   - target: The destination recording the revision.
        /// - Throws: `RecordingError` when the test backend rejects rendering.
        func render(
            _ update: HighlightUpdate,
            in target: RecordingTarget
        ) throws(RecordingError) {
            target.updateRevisions.append(update.snapshot.revision)
        }
    }

    /// Confirms backends can implement only complete snapshot rendering.
    @Test
    func fallsBackToCompleteSnapshotForIncrementalUpdate()
        throws(RecordingError)
    {
        let update = makeUpdate(revision: 8)
        let target = RecordingTarget()
        var renderer = CompleteSnapshotRenderer()

        try render(update, using: &renderer, in: target)

        #expect(target.snapshotRevisions == [8])
        #expect(target.updateRevisions.isEmpty)
    }

    /// Confirms generic dispatch preserves a backend's incremental path.
    @Test
    func dispatchesIncrementalBackendImplementation()
        throws(RecordingError)
    {
        let update = makeUpdate(revision: 9)
        let target = RecordingTarget()
        var renderer = IncrementalRenderer()

        try render(update, using: &renderer, in: target)

        #expect(target.snapshotRevisions.isEmpty)
        #expect(target.updateRevisions == [9])
    }

    /// Confirms primary associated types preserve an erased backend contract.
    @Test
    func storesRendererBehindTypedExistential() throws(RecordingError) {
        let update = makeUpdate(revision: 10)
        let target = RecordingTarget()
        var renderer: any HighlightRenderer<RecordingTarget, RecordingError> =
            CompleteSnapshotRenderer()

        try renderer.render(update, in: target)

        #expect(target.snapshotRevisions == [10])
    }

    /// Confirms renderer ranges include replacements and parser invalidations.
    @Test
    func mergesRangesRequiringRendering() {
        let snapshot = HighlightSnapshot(
            text: "01234567890123456789",
            language: .swift,
            revision: 1,
            highlights: []
        )
        let update = HighlightUpdate(
            replacedRange: UTF16Range(location: 4, length: 3),
            replacementRange: UTF16Range(location: 4, length: 3),
            invalidatedRanges: [
                UTF16Range(location: 14, length: 1),
                UTF16Range(location: 6, length: 3),
                UTF16Range(location: 2, length: 0),
                UTF16Range(location: 12, length: 2),
            ],
            snapshot: snapshot
        )

        #expect(
            update.rangesRequiringRendering == [
                UTF16Range(location: 4, length: 5),
                UTF16Range(location: 12, length: 3),
            ]
        )
    }

    /// Confirms updates without renderable text return no rendering ranges.
    @Test
    func omitsEmptyRenderingRanges() {
        let snapshot = HighlightSnapshot(
            text: "",
            language: .swift,
            revision: 1,
            highlights: []
        )
        let emptyRange = UTF16Range(location: 0, length: 0)
        let update = HighlightUpdate(
            replacedRange: emptyRange,
            replacementRange: emptyRange,
            invalidatedRanges: [emptyRange],
            snapshot: snapshot
        )

        #expect(update.rangesRequiringRendering.isEmpty)
    }

    /// Creates a minimal update for generic backend dispatch tests.
    ///
    /// - Parameter revision: The revision assigned to the latest snapshot.
    /// - Returns: An update containing one replacement range.
    private func makeUpdate(revision: UInt64) -> HighlightUpdate {
        let range = UTF16Range(location: 0, length: 1)
        return HighlightUpdate(
            replacedRange: range,
            replacementRange: range,
            invalidatedRanges: [],
            snapshot: HighlightSnapshot(
                text: "x",
                language: .swift,
                revision: revision,
                highlights: []
            )
        )
    }

    /// Renders an update through its generic backend contract.
    ///
    /// - Parameters:
    ///   - update: The incremental state to render.
    ///   - renderer: The backend receiving generic dispatch.
    ///   - target: The backend destination receiving the state.
    /// - Throws: The failure type declared by the backend.
    private func render<Renderer: HighlightRenderer>(
        _ update: HighlightUpdate,
        using renderer: inout Renderer,
        in target: Renderer.Target
    ) throws(Renderer.Failure) {
        try renderer.render(update, in: target)
    }
}
