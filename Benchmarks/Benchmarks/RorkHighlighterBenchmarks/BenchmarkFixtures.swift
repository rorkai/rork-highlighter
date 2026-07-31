import Foundation
import RorkHighlighter

/// Names the document scales exercised by the benchmark suite.
enum BenchmarkDocumentSize: String, CaseIterable, Sendable {
    /// Represents a source file of at least four kibibytes.
    case small

    /// Represents a source file of at least 128 kibibytes.
    case medium

    /// Represents a source file of at least one mebibyte.
    case large

    /// Returns the readable name used in benchmark output.
    var displayName: String {
        rawValue.capitalized
    }

    /// Returns the minimum UTF-16 length generated for this scale.
    var minimumUTF16Length: Int {
        switch self {
        case .small:
            4 * 1_024
        case .medium:
            128 * 1_024
        case .large:
            1_024 * 1_024
        }
    }
}

/// Holds one deterministic source document and its benchmark label.
struct BenchmarkSource: Sendable {
    /// Holds the name shown in benchmark results.
    let name: String

    /// Holds the complete source text passed to Rork Highlighter.
    let text: String
}

/// Produces deterministic source documents outside measured regions.
enum BenchmarkFixtures {
    /// Marks the fixed-width token changed by the incremental benchmark.
    static let revisionMarker = "1000"

    /// Holds Swift documents at each supported benchmark scale.
    static let swiftSources = BenchmarkDocumentSize.allCases.map { size in
        BenchmarkSource(
            name: size.displayName,
            text: makeSwiftSource(
                minimumUTF16Length: size.minimumUTF16Length
            )
        )
    }

    /// Holds an HTML document with embedded JavaScript and CSS.
    static let injectedHTML = BenchmarkSource(
        name: "Medium",
        text: makeInjectedHTML(
            minimumUTF16Length: BenchmarkDocumentSize.medium
                .minimumUTF16Length
        )
    )

    /// Returns the largest generated Swift document.
    static var largeSwiftSource: BenchmarkSource {
        guard let source = swiftSources.last else {
            preconditionFailure("The Swift benchmark fixtures are empty.")
        }
        return source
    }

    /// Locates the fixed-width revision token in a generated Swift document.
    ///
    /// - Parameter source: The generated source containing the marker.
    /// - Returns: The exact UTF-16 range occupied by the marker.
    static func revisionMarkerRange(
        in source: String
    ) -> UTF16Range {
        guard let range = source.range(of: revisionMarker) else {
            preconditionFailure(
                "The Swift benchmark fixture has no revision marker."
            )
        }
        let rangeInUTF16 = NSRange(range, in: source)
        return UTF16Range(
            location: rangeInUTF16.location,
            length: rangeInUTF16.length
        )
    }

    /// Builds valid Swift declarations until the requested scale is reached.
    ///
    /// - Parameter minimumUTF16Length: The minimum generated document length.
    /// - Returns: A deterministic Swift source document.
    private static func makeSwiftSource(
        minimumUTF16Length: Int
    ) -> String {
        var source = """
            import Foundation

            let revisionMarker = 1000

            """
        var index = 0

        while source.utf16.count < minimumUTF16Length {
            source += """
                struct Model\(index): Codable, Sendable {
                    let identifier: Int = \(index)
                    let title: String = "Item \(index)"

                    func displayTitle() -> String {
                        "\\(identifier): \\(title)"
                    }
                }

                """
            index += 1
        }
        return source
    }

    /// Builds HTML with nested JavaScript and CSS until the scale is reached.
    ///
    /// - Parameter minimumUTF16Length: The minimum generated document length.
    /// - Returns: A deterministic nested-language source document.
    private static func makeInjectedHTML(
        minimumUTF16Length: Int
    ) -> String {
        var source = "<!doctype html>\n<html><body>\n"
        var index = 0

        while source.utf16.count < minimumUTF16Length {
            source += #"""
                <section class="card-#(index)">
                    <h2>Card #(index)</h2>
                    <script type="module">
                        const state#(index) = { count: #(index), enabled: true };
                        document.querySelector(".card-#(index)")?.addEventListener("click", () => {
                            console.log(`Selected ${state#(index).count}`);
                        });
                    </script>
                    <style>
                        .card-#(index) { display: grid; gap: 12px; color: rgb(90, 212, 230); }
                    </style>
                </section>

                """#
            index += 1
        }
        source += "</body></html>\n"
        return source
    }
}
