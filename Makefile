.PHONY: build test format lint vendor-languages check-languages check-documentation check

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test

format:
	swift format format --recursive --in-place Package.swift Sources/RorkHighlighter Tests

lint:
	swift format lint --recursive --strict Package.swift Sources/RorkHighlighter Tests

vendor-languages:
	python3 Scripts/vendor_languages.py --update

check-languages:
	python3 Scripts/vendor_languages.py

check-documentation:
	python3 Scripts/check_documentation.py

check: lint check-languages build test check-documentation
