import AppKit
import Benchmark
import Foundation
import RorkHighlighter
import SwiftHighlight
import SwiftUI

/// Registers SwiftHighlight's Swift grammar once before measured work begins.
private actor SwiftHighlightRegistration {
    /// Tracks whether the shared highlighter is ready for measurements.
    private var isReady = false

    /// Registers Swift when the benchmark first requests prepared state.
    ///
    /// - Parameter highlighter: The shared SwiftHighlight engine.
    func prepare(_ highlighter: SwiftHighlight.Highlight) async {
        guard !isReady else {
            return
        }
        await highlighter.registerSwift()
        isReady = true
    }
}

/// Creates shared benchmark state and turns setup failures into diagnostics.
private enum ComparisonBenchmarkSetup {
    /// Creates Rork Highlighter with its complete bundled catalog.
    ///
    /// - Returns: A reusable highlighter ready for measured calls.
    static func makeRorkHighlighter() -> Highlighter {
        do {
            return try Highlighter()
        } catch {
            preconditionFailure(
                "Rork Highlighter initialization failed. \(error)"
            )
        }
    }

    /// Creates the persistent session used by incremental measurements.
    ///
    /// - Parameters:
    ///   - fixture: The initial source document.
    ///   - highlighter: The Rork highlighter that owns the language catalog.
    /// - Returns: An actor-isolated session ready for repeated edits.
    static func makeRorkSession(
        fixture: ComparisonFixture,
        highlighter: Highlighter
    ) -> HighlightSession {
        do {
            return try highlighter.makeSession(fixture.text, as: .swift)
        } catch {
            preconditionFailure(
                "Rork Highlighter session initialization failed. \(error)"
            )
        }
    }
}

/// Reuses one Rork Highlighter outside measured initialization work.
private let rorkHighlighter = ComparisonBenchmarkSetup.makeRorkHighlighter()

/// Reuses one HighlightKit engine outside measured initialization work.
private let highlightKitHighlighter = HighlightKitAdapter()

/// Reuses one SwiftHighlight actor outside measured initialization work.
private let swiftHighlightHighlighter = SwiftHighlight.Highlight()

/// Serializes one-time SwiftHighlight grammar registration.
private let swiftHighlightRegistration = SwiftHighlightRegistration()

/// Chooses stable sampling limits for one fixture size.
///
/// - Parameter fixture: The fixture whose workload determines sample cost.
/// - Returns: A benchmark configuration shared by every implementation.
private func configuration(
    for fixture: ComparisonFixture
) -> Benchmark.Configuration {
    let duration: Duration
    let iterations: Int
    switch fixture.name {
    case "4KiB":
        duration = .seconds(3)
        iterations = 100
    case "64KiB":
        duration = .seconds(5)
        iterations = 50
    default:
        duration = .seconds(10)
        iterations = 20
    }

    return .init(
        metrics: [
            .wallClock,
            .cpuTotal,
            .mallocCountTotal,
        ],
        warmupIterations: 2,
        maxDuration: duration,
        maxIterations: iterations
    )
}

/// Creates setup work that registers and validates SwiftHighlight.
///
/// - Parameter fixture: The fixture used to verify the registered grammar.
/// - Returns: An asynchronous setup hook for SwiftHighlight benchmarks.
private func swiftHighlightSetup(
    for fixture: ComparisonFixture
) -> Benchmark.BenchmarkSetupHook {
    {
        await swiftHighlightRegistration.prepare(
            swiftHighlightHighlighter
        )
        let result = await swiftHighlightHighlighter.parse(
            fixture.text,
            language: "swift"
        )
        precondition(
            result.errorRaised == nil,
            "SwiftHighlight rejected the shared Swift fixture."
        )
    }
}

/// Registers same-corpus benchmarks for every supported public workflow.
let benchmarks: @Sendable () -> Void = {
    for fixture in ComparisonFixtures.swiftSources {
        let fixtureConfiguration = configuration(for: fixture)
        let rorkControl: HighlightSnapshot
        do {
            rorkControl = try rorkHighlighter.highlight(
                fixture.text,
                as: .swift
            )
        } catch {
            preconditionFailure(
                "Rork Highlighter rejected the shared Swift fixture. \(error)"
            )
        }
        let highlightKitControl = highlightKitHighlighter.tokenCount(
            fixture.text
        )

        precondition(!rorkControl.highlights.isEmpty)
        precondition(highlightKitControl > 0)

        Benchmark(
            "HighlightResult/RorkHighlighter/\(fixture.name)",
            configuration: fixtureConfiguration
        ) { _ in
            blackHole(
                try rorkHighlighter.highlight(
                    fixture.text,
                    as: .swift
                ).highlights.count
            )
        }

        Benchmark(
            "HighlightResult/HighlightKit/\(fixture.name)",
            configuration: fixtureConfiguration
        ) { _ in
            blackHole(
                highlightKitHighlighter.tokenCount(fixture.text)
            )
        }

        Benchmark(
            "HighlightResult/SwiftHighlight/\(fixture.name)",
            configuration: fixtureConfiguration,
            closure: { _ in
                let result = await swiftHighlightHighlighter.parse(
                    fixture.text,
                    language: "swift"
                )
                blackHole(result.tokenTree.root.children.count)
            },
            setup: swiftHighlightSetup(for: fixture)
        )

        Benchmark(
            "NativeEndToEnd/RorkHighlighter/\(fixture.name)",
            configuration: fixtureConfiguration
        ) { _ in
            blackHole(
                try autoreleasepool {
                    let snapshot = try rorkHighlighter.highlight(
                        fixture.text,
                        as: .swift
                    )
                    return try snapshot.nsAttributedString(
                        theme: .rorkDark
                    ).length
                }
            )
        }

        Benchmark(
            "NativeEndToEnd/HighlightKit/\(fixture.name)",
            configuration: fixtureConfiguration
        ) { _ in
            blackHole(
                autoreleasepool {
                    highlightKitHighlighter.attributedStringLength(
                        fixture.text
                    )
                }
            )
        }

        Benchmark(
            "NativeEndToEnd/SwiftHighlight/\(fixture.name)",
            configuration: fixtureConfiguration,
            closure: { _ in
                let result = await swiftHighlightHighlighter.parse(
                    fixture.text,
                    language: "swift"
                )
                blackHole(
                    autoreleasepool {
                        let renderer =
                            SwiftHighlight.NSAttributedStringRenderer()
                        return renderer.render(result.tokenTree).length
                    }
                )
            },
            setup: swiftHighlightSetup(for: fixture)
        )

        Benchmark(
            "SwiftUIEndToEnd/RorkHighlighter/\(fixture.name)",
            configuration: fixtureConfiguration
        ) { _ in
            blackHole(
                try rorkHighlighter.highlight(
                    fixture.text,
                    as: .swift
                ).attributedString(theme: .rorkDark)
            )
        }

        Benchmark(
            "SwiftUIEndToEnd/SwiftHighlight/\(fixture.name)",
            configuration: fixtureConfiguration,
            closure: { _ in
                let renderer = SwiftHighlight.AttributedStringRenderer()
                let result = await swiftHighlightHighlighter.highlight(
                    fixture.text,
                    language: "swift",
                    renderer: renderer
                )
                blackHole(result.value)
            },
            setup: swiftHighlightSetup(for: fixture)
        )

        Benchmark(
            "HTMLEndToEnd/SwiftHighlight/\(fixture.name)",
            configuration: fixtureConfiguration,
            closure: { _ in
                let result = await swiftHighlightHighlighter.highlight(
                    fixture.text,
                    language: "swift"
                )
                blackHole(result.value.utf8.count)
            },
            setup: swiftHighlightSetup(for: fixture)
        )
    }

    let editFixture = ComparisonFixtures.editingFixture
    let editConfiguration = configuration(for: editFixture)
    let rorkSession = ComparisonBenchmarkSetup.makeRorkSession(
        fixture: editFixture,
        highlighter: rorkHighlighter
    )

    Benchmark(
        "EditorEdit/RorkHighlighter/\(editFixture.name)",
        configuration: editConfiguration
    ) { _ in
        let revision = await rorkSession.currentRevision
        let replacement =
            revision.isMultiple(of: 2)
            ? ComparisonFixtures.replacementMarker
            : ComparisonFixtures.revisionMarker
        blackHole(
            try await rorkSession.replaceCharacters(
                in: editFixture.markerRange,
                with: replacement
            ).snapshot.highlights.count
        )
    }

    Benchmark(
        "EditorEdit/HighlightKitFullPass/\(editFixture.name)",
        configuration: editConfiguration
    ) { benchmark in
        let source =
            benchmark.currentIteration.isMultiple(of: 2)
            ? editFixture.editedText
            : editFixture.text
        blackHole(highlightKitHighlighter.tokenCount(source))
    }

    Benchmark(
        "EditorEdit/SwiftHighlightFullPass/\(editFixture.name)",
        configuration: editConfiguration,
        closure: { benchmark in
            let source =
                benchmark.currentIteration.isMultiple(of: 2)
                ? editFixture.editedText
                : editFixture.text
            let result = await swiftHighlightHighlighter.parse(
                source,
                language: "swift"
            )
            blackHole(result.tokenTree.root.children.count)
        },
        setup: swiftHighlightSetup(for: editFixture)
    )
}
