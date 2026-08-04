# Benchmarks

The benchmark package measures Rork Highlighter through its public API. It is
separate from the library package, so consumers do not resolve or build the
benchmark framework.

The suite uses the Ordo One Benchmark package at an exact version. It reports
wall-clock time, CPU time, allocation count, peak resident memory, and
throughput on macOS and Linux.

## Runtime measurements

Run every benchmark from the repository root.

```sh
make benchmark
```

Linux uses jemalloc-backed allocation metrics. Install its development headers
before building the benchmark package on Debian or Ubuntu.

```sh
sudo apt-get install libjemalloc-dev
```

Pass additional command-plugin arguments when a focused run is more useful.

```sh
make benchmark BENCHMARK_ARGUMENTS="--filter '.*Highlight/Swift.*'"
```

The suite generates its inputs before measurement begins. Swift fixtures cover
roughly 4 KiB, 128 KiB, and 1 MiB documents. The workloads include standard
catalog initialization, one-shot Swift highlighting, HTML with JavaScript and
CSS injections, a fixed-width incremental edit, hierarchical theme resolution,
native attributed rendering, and incremental TextKit storage rendering where
those frameworks are available.

Incremental coverage includes fixed-width replacements near both ends of the
document and edits that alternate between shorter and longer text. The
variable-width workload exercises range rebasing for every retained capture
after the edit.

Performance results should only be compared on the same hardware, operating
system, and Swift toolchain. The first benchmark PR deliberately records no
regression thresholds because a stable baseline must come from repeated runs on
a consistent host.

## Cross-library comparisons

The opt-in comparison package runs Rork Highlighter and other implementations
against byte-identical generated Swift documents. It remains separate from this
regression suite so ordinary builds do not resolve competitor dependencies.

```sh
make benchmark-comparison \
  COMPARISON_BENCHMARK_ARGUMENTS="--metric wallClock --time-units microseconds --no-progress"
```

The [comparison guide](Comparison/README.md) documents dependency pins, shared
fixture integrity, JavaScript measurements, workload boundaries, focused runs,
and reporting constraints.

## Distribution measurements

Measure a clean release build and its source, object, executable, and resource
footprints.

```sh
make measure-distribution
```

The measurement resolves dependencies before timing and then asks SwiftPM to
clean the probe package. Network fetches are therefore excluded from the build
duration while every compiled product is rebuilt.

The command emits sorted JSON containing the Git revision, working-tree state,
host and toolchain, clean build duration, generated parser source size and line
count, compiled parser object size, linked probe size, bundled query resources,
and complete linked product size. Save a result when an external system needs
to retain it.

```sh
python3 Scripts/measure_distribution.py \
    --output .build/distribution-metrics.json
```

The output path belongs under ignored build output unless a deliberate,
machine-qualified baseline is being reviewed.
