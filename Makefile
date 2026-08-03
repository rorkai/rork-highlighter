PREVIEW_PACKAGE := Tools/PreviewGenerator
PREVIEW_SCRATCH := .build/preview
PREVIEW_OUTPUT := Sources/RorkHighlighter/RorkHighlighter.docc/Resources/swift-attributed-output.png
BENCHMARK_PACKAGE := Benchmarks
BENCHMARK_SCRATCH := .build/benchmarks
BENCHMARK_ARGUMENTS ?=
COMPARISON_PACKAGE := Benchmarks/Comparison
COMPARISON_SCRATCH := .build/comparison-benchmarks
COMPARISON_JAVASCRIPT := $(COMPARISON_PACKAGE)/JavaScript
COMPARISON_BENCHMARK_ARGUMENTS ?=
JAVASCRIPT_BENCHMARK_ARGUMENTS ?=
DISTRIBUTION_PROBE_PACKAGE := Tools/DistributionProbe
DISTRIBUTION_PROBE_SCRATCH := .build/distribution-probe
PARSER_PACK_OUTPUT ?= .build/parser-pack
PARSER_PACK_ARGUMENTS ?=

.PHONY: build test format lint preview benchmark comparison-fixtures comparison-javascript-dependencies benchmark-comparison benchmark-comparison-swift benchmark-comparison-javascript check-comparison measure-distribution parser-xcframework vendor-languages check-languages check-documentation check-preview check-parser-xcframework check-benchmarks check

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test

format:
	swift format format --recursive --in-place Package.swift Sources/RorkHighlighter Tests $(PREVIEW_PACKAGE)/Package.swift $(PREVIEW_PACKAGE)/Sources $(BENCHMARK_PACKAGE)/Package.swift $(BENCHMARK_PACKAGE)/Benchmarks $(COMPARISON_PACKAGE)/Package.swift $(COMPARISON_PACKAGE)/Benchmarks $(DISTRIBUTION_PROBE_PACKAGE)/Package.swift $(DISTRIBUTION_PROBE_PACKAGE)/Sources

lint:
	swift format lint --recursive --strict Package.swift Sources/RorkHighlighter Tests $(PREVIEW_PACKAGE)/Package.swift $(PREVIEW_PACKAGE)/Sources $(BENCHMARK_PACKAGE)/Package.swift $(BENCHMARK_PACKAGE)/Benchmarks $(COMPARISON_PACKAGE)/Package.swift $(COMPARISON_PACKAGE)/Benchmarks $(DISTRIBUTION_PROBE_PACKAGE)/Package.swift $(DISTRIBUTION_PROBE_PACKAGE)/Sources

preview:
	swift run --package-path $(PREVIEW_PACKAGE) --scratch-path $(PREVIEW_SCRATCH) PreviewGenerator "$(PREVIEW_OUTPUT)"

benchmark:
	swift package --package-path $(BENCHMARK_PACKAGE) --scratch-path $(BENCHMARK_SCRATCH) benchmark --target RorkHighlighterBenchmarks $(BENCHMARK_ARGUMENTS)

comparison-fixtures:
	python3 Scripts/generate_comparison_fixtures.py

comparison-javascript-dependencies:
	npm --prefix $(COMPARISON_JAVASCRIPT) ci --ignore-scripts --no-audit --no-fund

benchmark-comparison: benchmark-comparison-swift benchmark-comparison-javascript

benchmark-comparison-swift: comparison-fixtures
	swift package --package-path $(COMPARISON_PACKAGE) --scratch-path $(COMPARISON_SCRATCH) benchmark --target HighlighterComparisonBenchmarks $(COMPARISON_BENCHMARK_ARGUMENTS)

benchmark-comparison-javascript: comparison-fixtures comparison-javascript-dependencies
	npm --prefix $(COMPARISON_JAVASCRIPT) run benchmark -- $(JAVASCRIPT_BENCHMARK_ARGUMENTS)

check-comparison: comparison-fixtures comparison-javascript-dependencies
	swift build --package-path $(COMPARISON_PACKAGE) --scratch-path $(COMPARISON_SCRATCH) --target HighlighterComparisonBenchmarks -Xswiftc -warnings-as-errors
	npm --prefix $(COMPARISON_JAVASCRIPT) test

measure-distribution:
	python3 Scripts/measure_distribution.py

parser-xcframework:
	python3 Scripts/build_parser_xcframework.py --output-directory "$(PARSER_PACK_OUTPUT)" $(PARSER_PACK_ARGUMENTS)

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

ifeq ($(shell uname -s),Darwin)
check-parser-xcframework:
	python3 Scripts/build_parser_xcframework.py --host-only --allow-dirty --output-directory .build/parser-pack-check
else
check-parser-xcframework:
	@echo "The parser XCFramework check is skipped on non-macOS hosts."
endif

check-benchmarks:
	swift build --package-path $(BENCHMARK_PACKAGE) --scratch-path $(BENCHMARK_SCRATCH) --target RorkHighlighterBenchmarks -Xswiftc -warnings-as-errors
	swift build --package-path $(DISTRIBUTION_PROBE_PACKAGE) --scratch-path $(DISTRIBUTION_PROBE_SCRATCH) --target DistributionProbe -Xswiftc -warnings-as-errors

check: lint check-languages build test check-documentation check-preview check-parser-xcframework check-benchmarks
