PREVIEW_PACKAGE := Tools/PreviewGenerator
PREVIEW_SCRATCH := .build/preview
PREVIEW_OUTPUT := Sources/RorkHighlighter/RorkHighlighter.docc/Resources/swift-attributed-output.png
BENCHMARK_PACKAGE := Benchmarks
BENCHMARK_SCRATCH := .build/benchmarks
BENCHMARK_ARGUMENTS ?=
DISTRIBUTION_PROBE_PACKAGE := Tools/DistributionProbe
DISTRIBUTION_PROBE_SCRATCH := .build/distribution-probe

.PHONY: build test format lint preview benchmark measure-distribution vendor-languages check-languages check-documentation check-preview check-benchmarks check

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test

format:
	swift format format --recursive --in-place Package.swift Sources/RorkHighlighter Tests $(PREVIEW_PACKAGE)/Package.swift $(PREVIEW_PACKAGE)/Sources $(BENCHMARK_PACKAGE)/Package.swift $(BENCHMARK_PACKAGE)/Benchmarks $(DISTRIBUTION_PROBE_PACKAGE)/Package.swift $(DISTRIBUTION_PROBE_PACKAGE)/Sources

lint:
	swift format lint --recursive --strict Package.swift Sources/RorkHighlighter Tests $(PREVIEW_PACKAGE)/Package.swift $(PREVIEW_PACKAGE)/Sources $(BENCHMARK_PACKAGE)/Package.swift $(BENCHMARK_PACKAGE)/Benchmarks $(DISTRIBUTION_PROBE_PACKAGE)/Package.swift $(DISTRIBUTION_PROBE_PACKAGE)/Sources

preview:
	swift run --package-path $(PREVIEW_PACKAGE) --scratch-path $(PREVIEW_SCRATCH) PreviewGenerator "$(PREVIEW_OUTPUT)"

benchmark:
	swift package --package-path $(BENCHMARK_PACKAGE) --scratch-path $(BENCHMARK_SCRATCH) benchmark --target RorkHighlighterBenchmarks $(BENCHMARK_ARGUMENTS)

measure-distribution:
	python3 Scripts/measure_distribution.py

vendor-languages:
	python3 Scripts/vendor_languages.py --update

check-languages:
	python3 Scripts/vendor_languages.py

check-documentation:
	python3 -m unittest discover -s Scripts/tests -p "test_*.py"
	python3 Scripts/check_documentation.py

ifeq ($(shell uname -s),Darwin)
check-preview:
	swift build --package-path $(PREVIEW_PACKAGE) --scratch-path $(PREVIEW_SCRATCH) --target PreviewGenerator -Xswiftc -warnings-as-errors
else
check-preview:
	@echo "The AppKit preview build is skipped on non-macOS hosts."
endif

check-benchmarks:
	swift build --package-path $(BENCHMARK_PACKAGE) --scratch-path $(BENCHMARK_SCRATCH) --target RorkHighlighterBenchmarks -Xswiftc -warnings-as-errors
	swift build --package-path $(DISTRIBUTION_PROBE_PACKAGE) --scratch-path $(DISTRIBUTION_PROBE_SCRATCH) --target DistributionProbe -Xswiftc -warnings-as-errors

check: lint check-languages build test check-documentation check-preview check-benchmarks
