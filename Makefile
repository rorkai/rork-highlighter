PREVIEW_PACKAGE := Tools/PreviewGenerator
PREVIEW_OUTPUT := Sources/RorkHighlighter/RorkHighlighter.docc/Resources/swift-attributed-output.png

.PHONY: build test format lint preview vendor-languages check-languages check-documentation check-preview check

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test

format:
	swift format format --recursive --in-place Package.swift Sources/RorkHighlighter Tests $(PREVIEW_PACKAGE)/Package.swift $(PREVIEW_PACKAGE)/Sources

lint:
	swift format lint --recursive --strict Package.swift Sources/RorkHighlighter Tests $(PREVIEW_PACKAGE)/Package.swift $(PREVIEW_PACKAGE)/Sources

preview:
	swift run --package-path $(PREVIEW_PACKAGE) --scratch-path .build PreviewGenerator "$(PREVIEW_OUTPUT)"

vendor-languages:
	python3 Scripts/vendor_languages.py --update

check-languages:
	python3 Scripts/vendor_languages.py

check-documentation:
	python3 Scripts/check_documentation.py

ifeq ($(shell uname -s),Darwin)
check-preview:
	swift build --package-path $(PREVIEW_PACKAGE) --scratch-path .build --target PreviewGenerator -Xswiftc -warnings-as-errors
else
check-preview:
	@echo "The AppKit preview build is skipped on non-macOS hosts."
endif

check: lint check-languages build test check-documentation check-preview
