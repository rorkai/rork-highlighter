# Comparison benchmarks

This opt-in package runs Rork Highlighter, HighlightKit, swift-highlight, and
the original highlight.js implementation against the same generated Swift
documents. It exists outside the production package and the regular regression
suite, so library consumers and normal validation never resolve competitor
dependencies.

The suite is intended for release investigations and reproducible performance
claims. The regular benchmark package remains the source of stable regression
workloads for Rork Highlighter itself.

## Running the complete comparison

Run every Swift and JavaScript workload from the repository root:

```sh
make benchmark-comparison \
  COMPARISON_BENCHMARK_ARGUMENTS="--metric wallClock --time-units microseconds --no-progress"
```

The command generates fixtures, resolves the isolated Swift package, installs
the exact npm lockfile, and runs both runtime suites. Node.js 20 or newer is
required. The Swift comparison requires Swift 6.1 or newer and macOS 15 or
newer because HighlightKit uses those deployment and toolchain versions. The
manual `Comparison benchmarks` GitHub workflow runs the same validation and
measurement sequence on macOS.

Run a focused Swift comparison when iterating on one workload:

```sh
make benchmark-comparison-swift \
  COMPARISON_BENCHMARK_ARGUMENTS="--filter '.*256KiB$$' --metric wallClock --time-units microseconds --no-progress"
```

Run a focused highlight.js comparison with an optional JSON artifact:

```sh
make benchmark-comparison-javascript \
  JAVASCRIPT_BENCHMARK_ARGUMENTS="--filter '256KiB$$' --json ../.build/highlightjs-results.json"
```

Validate both harnesses without running the complete measurement matrix:

```sh
make check-comparison
```

## Shared fixtures

`Scripts/generate_comparison_fixtures.py` creates valid ASCII Swift sources of
roughly 4 KiB, 64 KiB, and 256 KiB. Generated files and their manifest live in
ignored build output under `Benchmarks/Comparison/.build/fixtures`.

The manifest records each file's exact byte count, UTF-16 length, line count,
and SHA-256 digest. Both runtimes validate those values before registering any
measurements. This guarantees that every implementation receives the same
bytes without committing thousands of synthetic source lines.

Each size uses two unmeasured warm-up iterations. The 4 KiB workload accepts up
to 100 samples over three seconds, the 64 KiB workload accepts up to 50 samples
over five seconds, and the 256 KiB workload accepts up to 20 samples over ten
seconds. Highlighter construction and language registration finish before
measurement begins.

The Swift suite uses Ordo One Benchmark's histogram percentiles. The Node
runner reports nearest-rank percentiles from individual `hrtime.bigint()`
samples. Median comparisons are more robust than comparing their highest
percentiles directly. Node heap and garbage-collection behavior is not
comparable with Swift allocation counts, so the JavaScript table reports
latency only.

## Workload boundaries

The `HighlightResult` group exercises each Swift library's public semantic
result. Rork Highlighter returns Tree-sitter query captures in Foundation-native
UTF-16 ranges, HighlightKit returns flat tokens, and swift-highlight returns its
token tree. These outputs have different richness, so the group represents each
library's practical public highlighting boundary rather than an identical
internal parser operation.

Swift is the canonical corpus because it is supported by every compared engine
and exercises the native output APIs relevant to Apple-platform clients.

The `NativeEndToEnd` and `SwiftUIEndToEnd` groups include highlighting and
rendering. HighlightKit has no direct SwiftUI `AttributedString` output and is
therefore absent from that group. Swift 6 does not permit swift-highlight's
generic actor method to return `NSAttributedString` because the Foundation type
is not `Sendable`. Its native workload uses the same public `parse` and
`NSAttributedStringRenderer.render` components while keeping the rendered value
on the calling task. The native workloads use each library's shipped built-in
theme because their theme models are not interchangeable. They measure
practical end-to-end output rather than an identical count of style attributes.

The `HTMLEndToEnd` group compares swift-highlight with the original highlight.js
implementation. Highlight.js has no public parse-only API and its documented
highlighting result contains escaped HTML, so it must not be presented as a raw
parser comparison with Rork Highlighter.

The `EditorEdit` group measures Rork Highlighter's arbitrary incremental edit.
The other libraries do not expose an equivalent editing session, so their
workloads are explicitly named `FullPass` and re-highlight the complete source.

## Reproducibility

The comparison package pins HighlightKit 0.2.0, swift-highlight revision
`6571a6d3177780feb3cc3e02d70081f4882aa339`, Ordo One Benchmark 1.36.2, and
highlight.js 11.11.1. The production package does not depend on any of them.

Compare results only when hardware, operating system, Swift toolchain, Node.js
runtime, fixture digests, build configuration, and benchmark filters match.
Run at least two campaigns before publishing a ratio. GitHub-hosted runner
results are useful for smoke testing but are not stable regression thresholds.

Performance does not prove highlighting correctness. Accuracy claims require a
separate syntax corpus with expected captures for malformed input, nested
languages, interpolation, raw strings, comments, and modern language features.
