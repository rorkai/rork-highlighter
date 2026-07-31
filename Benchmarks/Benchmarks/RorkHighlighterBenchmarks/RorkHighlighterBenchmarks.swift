import Benchmark
import RorkHighlighter

#if canImport(AppKit)
    import AppKit
#endif

#if canImport(SwiftUI)
    import SwiftUI
#endif

/// Creates benchmark state before any measured iteration begins.
private enum BenchmarkSetup {
    /// Creates the standard highlighter or stops on an invalid bundled pack.
    ///
    /// - Returns: A highlighter containing every bundled language.
    static func makeHighlighter() -> Highlighter {
        do {
            return try Highlighter()
        } catch {
            preconditionFailure(
                "Could not initialize Rork Highlighter: \(error)"
            )
        }
    }

    /// Highlights a fixture before rendering measurements begin.
    ///
    /// - Parameters:
    ///   - fixture: The source document to highlight.
    ///   - highlighter: The shared highlighter used for setup.
    /// - Returns: The complete immutable highlighting snapshot.
    static func snapshot(
        for fixture: BenchmarkSource,
        using highlighter: Highlighter
    ) -> HighlightSnapshot {
        do {
            return try highlighter.highlight(fixture.text, as: .swift)
        } catch {
            preconditionFailure(
                "Could not highlight the \(fixture.name) fixture: \(error)"
            )
        }
    }

    /// Opens the persistent session used by incremental measurements.
    ///
    /// - Parameters:
    ///   - fixture: The initial source document.
    ///   - highlighter: The highlighter that creates the session.
    /// - Returns: An actor-isolated session ready for incremental edits.
    static func session(
        for fixture: BenchmarkSource,
        using highlighter: Highlighter
    ) -> HighlightSession {
        do {
            return try highlighter.makeSession(fixture.text, as: .swift)
        } catch {
            preconditionFailure(
                "Could not open the incremental fixture: \(error)"
            )
        }
    }
}

/// Registers benchmarks for the public highlighting and rendering workflows.
let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [
            .wallClock,
            .cpuTotal,
            .mallocCountTotal,
            .peakMemoryResident,
            .throughput,
        ],
        warmupIterations: 2,
        maxDuration: .seconds(2),
        maxIterations: 100
    )

    Benchmark("Catalog/Initialize") { _ in
        blackHole(try Highlighter())
    }

    let highlighter = BenchmarkSetup.makeHighlighter()
    let snapshots = BenchmarkFixtures.swiftSources.map { fixture in
        (
            fixture: fixture,
            snapshot: BenchmarkSetup.snapshot(
                for: fixture,
                using: highlighter
            )
        )
    }

    for fixture in BenchmarkFixtures.swiftSources {
        Benchmark("Highlight/Swift/\(fixture.name)") { _ in
            blackHole(
                try highlighter.highlight(
                    fixture.text,
                    as: .swift
                )
            )
        }
    }

    let injectedHTML = BenchmarkFixtures.injectedHTML
    Benchmark("Highlight/HTMLWithInjections/\(injectedHTML.name)") { _ in
        blackHole(
            try highlighter.highlight(
                injectedHTML.text,
                as: .html
            )
        )
    }

    let largeFixture = BenchmarkFixtures.largeSwiftSource
    let markerRange = BenchmarkFixtures.revisionMarkerRange(
        in: largeFixture.text
    )
    let session = BenchmarkSetup.session(
        for: largeFixture,
        using: highlighter
    )
    let incrementalEdit: @Sendable (Benchmark) async throws -> Void = { benchmark in
        let replacement =
            benchmark.currentIteration.isMultiple(of: 2)
            ? "2000"
            : BenchmarkFixtures.revisionMarker

        #if compiler(>=6.1)
            let update = try await session.replaceCharacters(
                in: markerRange,
                with: replacement
            )
        #else
            // Swift 6.0 imports this cross-package actor call as synchronous.
            let update = try session.replaceCharacters(
                in: markerRange,
                with: replacement
            )
        #endif
        blackHole(
            update
        )
    }
    Benchmark(
        "Highlight/IncrementalEdit/Large",
        closure: incrementalEdit
    )

    let variableEditSession = BenchmarkSetup.session(
        for: largeFixture,
        using: highlighter
    )
    let variableWidthEdit: @Sendable (Benchmark) async throws -> Void = { _ in
        #if compiler(>=6.1)
            let revision = await variableEditSession.currentRevision
        #else
            // Swift 6.0 imports this cross-package actor access as synchronous.
            let revision = variableEditSession.currentRevision
        #endif
        let usesExpandedMarker = !revision.isMultiple(of: 2)
        let currentRange = UTF16Range(
            location: markerRange.location,
            length:
                usesExpandedMarker
                ? BenchmarkFixtures.expandedRevisionMarker.utf16.count
                : BenchmarkFixtures.revisionMarker.utf16.count
        )
        let replacement =
            usesExpandedMarker
            ? BenchmarkFixtures.revisionMarker
            : BenchmarkFixtures.expandedRevisionMarker

        #if compiler(>=6.1)
            let update = try await variableEditSession.replaceCharacters(
                in: currentRange,
                with: replacement
            )
        #else
            // Swift 6.0 imports this cross-package actor call as synchronous.
            let update = try variableEditSession.replaceCharacters(
                in: currentRange,
                with: replacement
            )
        #endif
        blackHole(update)
    }
    Benchmark(
        "Highlight/IncrementalVariableWidthEdit/Large",
        closure: variableWidthEdit
    )

    let tailMarkerRange = BenchmarkFixtures.tailRevisionMarkerRange(
        in: largeFixture.text
    )
    let tailEditSession = BenchmarkSetup.session(
        for: largeFixture,
        using: highlighter
    )
    let tailEdit: @Sendable (Benchmark) async throws -> Void = { benchmark in
        let replacement =
            benchmark.currentIteration.isMultiple(of: 2)
            ? "4000"
            : BenchmarkFixtures.tailRevisionMarker

        #if compiler(>=6.1)
            let update = try await tailEditSession.replaceCharacters(
                in: tailMarkerRange,
                with: replacement
            )
        #else
            // Swift 6.0 imports this cross-package actor call as synchronous.
            let update = try tailEditSession.replaceCharacters(
                in: tailMarkerRange,
                with: replacement
            )
        #endif
        blackHole(update)
    }
    Benchmark(
        "Highlight/IncrementalTailEdit/Large",
        closure: tailEdit
    )

    guard let largeSnapshot = snapshots.last?.snapshot else {
        preconditionFailure("The Swift benchmark snapshots are empty.")
    }
    Benchmark("Theme/Resolve/Large") { _ in
        for highlight in largeSnapshot.highlights {
            blackHole(HighlightTheme.rorkDark.style(for: highlight))
        }
    }

    #if canImport(SwiftUI)
        for value in snapshots {
            Benchmark("Render/AttributedString/\(value.fixture.name)") { _ in
                blackHole(
                    try value.snapshot.attributedString(
                        theme: .rorkDark
                    )
                )
            }
        }
    #endif

    #if canImport(AppKit)
        for value in snapshots {
            Benchmark("Render/NSAttributedString/\(value.fixture.name)") { _ in
                blackHole(
                    try value.snapshot.nsAttributedString(
                        theme: .rorkDark
                    )
                )
            }
        }
    #endif
}
