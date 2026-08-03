#!/usr/bin/env python3
"""Verifies documentation for maintained Swift and authored C declarations."""

from __future__ import annotations

import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any


# The repository root is the parent of the Scripts directory.
REPOSITORY_ROOT = Path(__file__).resolve().parent.parent

# Only the maintained Swift module participates in documentation coverage.
MODULE_NAME = "RorkHighlighter"

# Emitted declarations must originate in this directory to be maintained code.
SOURCE_DIRECTORY = REPOSITORY_ROOT / "Sources" / MODULE_NAME

# Test declarations follow the same documentation policy as library code.
TEST_SOURCE_DIRECTORY = (
    REPOSITORY_ROOT / "Tests" / f"{MODULE_NAME}Tests"
)

# Preview tool declarations follow the same documentation policy as library
# code.
PREVIEW_TOOL_SOURCE_DIRECTORY = (
    REPOSITORY_ROOT
    / "Tools"
    / "PreviewGenerator"
    / "Sources"
    / "PreviewGenerator"
)

# Benchmark declarations follow the same documentation policy as library code.
BENCHMARK_SOURCE_DIRECTORY = (
    REPOSITORY_ROOT
    / "Benchmarks"
    / "Benchmarks"
    / "RorkHighlighterBenchmarks"
)

# Comparison benchmark declarations remain maintained despite their opt-in
# dependency graph.
COMPARISON_BENCHMARK_SOURCE_DIRECTORY = (
    REPOSITORY_ROOT
    / "Benchmarks"
    / "Comparison"
    / "Benchmarks"
    / "HighlighterComparisonBenchmarks"
)

# Distribution probe declarations remain maintained even though they are
# outside the public package.
DISTRIBUTION_PROBE_SOURCE_DIRECTORY = (
    REPOSITORY_ROOT
    / "Tools"
    / "DistributionProbe"
    / "Sources"
    / "DistributionProbe"
)

# Authored C declarations use the same line-oriented documentation style.
C_HEADER_DIRECTORY = (
    REPOSITORY_ROOT
    / "Sources"
    / "CRorkHighlighterParsers"
    / "include"
)

# Authored C translation units explain their purpose before implementation.
C_SOURCE_DIRECTORY = (
    REPOSITORY_ROOT
    / "Sources"
    / "CRorkHighlighterParsers"
    / "wrappers"
)

# The package's DocC catalog is converted on hosts that provide Xcode.
DOCC_CATALOG = SOURCE_DIRECTORY / f"{MODULE_NAME}.docc"

# Private declarations lose DocC metadata in Swift symbol graphs, so their
# source spelling is checked separately.
PRIVATE_DECLARATION = re.compile(
    r"^\s*(?:@\S+\s+)*(?:private|fileprivate)\b.*"
    r"\b(?:actor|class|enum|struct|protocol|extension|typealias|"
    r"associatedtype|init|subscript|func|var|let)\b"
)

# Extension blocks do not appear as ordinary symbol graph declarations.
EXTENSION_DECLARATION = re.compile(
    r"^(?:(?:public|package|internal|fileprivate|private)\s+)?"
    r"extension\b"
)

# Supporting sources can be indented by conditional compilation blocks, so
# declaration scope is considered separately from raw indentation.
SUPPORTING_SWIFT_DECLARATION = re.compile(
    r"^(?P<indent> *)(?:@\S+\s+)*"
    r"(?:(?:public|open|(?:package|internal|fileprivate|private)"
    r"(?:\(set\))?|final|"
    r"indirect|static|class|override|required|convenience|mutating|"
    r"nonmutating|nonisolated|isolated|lazy)\s+)*"
    r"(?P<kind>actor|class|enum|struct|protocol|extension|typealias|"
    r"associatedtype|init|deinit|subscript|func|var|let|case)\b"
)

# These declarations establish a scope whose direct members need
# documentation.
SUPPORTING_SWIFT_TYPE_KINDS = frozenset(
    {"actor", "class", "enum", "struct", "protocol", "extension"}
)

# Multiline fixture contents are excluded before declaration matching.
SWIFT_MULTILINE_STRING_OPENING = re.compile(
    r'(?P<hashes>#+)?"""'
)

# Conditional compilation branches establish an indentation baseline without
# introducing a declaration scope.
SWIFT_CONDITIONAL_COMPILATION_BRANCH = re.compile(
    r"^(?P<indent> *)#(?:if|elseif|else)\b"
)

# Public C declarations are confined to authored headers outside vendor trees.
C_DECLARATION = re.compile(
    r"^\s*(?:typedef\s+.+;|.+\([^;{}]*\);)\s*$"
)


def dump_symbol_graph() -> None:
    """Builds a private-access symbol graph for the package."""
    subprocess.run(
        [
            "swift",
            "package",
            "dump-symbol-graph",
            "--minimum-access-level",
            "private",
            "--skip-synthesized-members",
        ],
        cwd=REPOSITORY_ROOT,
        check=True,
    )


def symbol_graph_paths() -> list[Path]:
    """Returns every emitted graph fragment for the maintained module."""
    build_directory = REPOSITORY_ROOT / ".build"
    return sorted(
        build_directory.glob(
            f"**/symbolgraph/{MODULE_NAME}*.symbols.json"
        )
    )


def load_symbols(paths: list[Path]) -> list[dict[str, Any]]:
    """Loads unique declarations from emitted symbol graph fragments."""
    symbols_by_identifier: dict[str, dict[str, Any]] = {}
    for path in paths:
        with path.open(encoding="utf-8") as file:
            graph = json.load(file)
        for symbol in graph.get("symbols", []):
            precise_identifier = symbol["identifier"]["precise"]
            symbols_by_identifier[precise_identifier] = symbol
    return list(symbols_by_identifier.values())


def has_documentation(symbol: dict[str, Any]) -> bool:
    """Returns whether a declaration has at least one nonempty DocC line."""
    lines = symbol.get("docComment", {}).get("lines", [])
    return any(line.get("text", "").strip() for line in lines)


def display_name(symbol: dict[str, Any]) -> str:
    """Returns a readable declaration path for diagnostics."""
    path_components = symbol.get("pathComponents", [])
    if path_components:
        return ".".join(path_components)
    return symbol.get("names", {}).get("title", "<unknown declaration>")


def undocumented_symbols(
    symbols: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Returns emitted declarations that should have DocC comments."""
    return sorted(
        (
            symbol
            for symbol in symbols
            if symbol.get("accessLevel") not in {"private", "fileprivate"}
            and symbol.get("location", {})
            .get("uri", "")
            .startswith(SOURCE_DIRECTORY.as_uri())
            and not has_documentation(symbol)
        ),
        key=display_name,
    )


def swift_source_paths() -> list[Path]:
    """Returns maintained Swift source files in the library target."""
    return sorted(SOURCE_DIRECTORY.rglob("*.swift"))


def swift_test_paths() -> list[Path]:
    """Returns maintained Swift source files in the test target."""
    return sorted(TEST_SOURCE_DIRECTORY.rglob("*.swift"))


def swift_preview_tool_paths() -> list[Path]:
    """Returns maintained Swift source files in the preview tool."""
    return sorted(PREVIEW_TOOL_SOURCE_DIRECTORY.rglob("*.swift"))


def swift_benchmark_paths() -> list[Path]:
    """Returns maintained Swift source files in the benchmark suite."""
    return sorted(BENCHMARK_SOURCE_DIRECTORY.rglob("*.swift"))


def swift_comparison_benchmark_paths() -> list[Path]:
    """Returns maintained Swift sources in the comparison benchmark."""
    return sorted(COMPARISON_BENCHMARK_SOURCE_DIRECTORY.rglob("*.swift"))


def swift_distribution_probe_paths() -> list[Path]:
    """Returns maintained Swift source files in the distribution probe."""
    return sorted(DISTRIBUTION_PROBE_SOURCE_DIRECTORY.rglob("*.swift"))


def c_header_paths() -> list[Path]:
    """Returns authored C headers exposed by the parser target."""
    return sorted(C_HEADER_DIRECTORY.rglob("*.h"))


def c_source_paths() -> list[Path]:
    """Returns authored C translation units outside the vendor tree."""
    return sorted(C_SOURCE_DIRECTORY.rglob("*.c"))


def has_leading_doc_comment(lines: list[str], index: int) -> bool:
    """Checks the declaration's nearest meaningful preceding source line."""
    preceding_index = index - 1
    while preceding_index >= 0:
        stripped = lines[preceding_index].strip()
        if not stripped:
            return False
        if stripped.startswith("@") or stripped.startswith("#"):
            preceding_index -= 1
            continue
        return stripped.startswith("///") or stripped.endswith("*/")
    return False


def is_supporting_swift_declaration(
    lines: list[str],
    index: int,
) -> bool:
    """Returns whether a supporting declaration is outside local scope."""
    match = SUPPORTING_SWIFT_DECLARATION.match(lines[index])
    if match is None:
        return False

    indentation = len(match.group("indent"))
    for preceding_line in reversed(lines[:index]):
        branch_match = SWIFT_CONDITIONAL_COMPILATION_BRANCH.match(
            preceding_line
        )
        if branch_match is not None:
            branch_indentation = len(branch_match.group("indent"))
            if branch_indentation < indentation:
                indentation = branch_indentation
            continue

        enclosing_match = SUPPORTING_SWIFT_DECLARATION.match(
            preceding_line
        )
        if enclosing_match is None:
            continue
        enclosing_indentation = len(enclosing_match.group("indent"))
        if enclosing_indentation >= indentation:
            continue
        if enclosing_match.group("kind") not in SUPPORTING_SWIFT_TYPE_KINDS:
            return False
        indentation = enclosing_indentation
    return True


def swift_multiline_string_content_lines(
    lines: list[str],
) -> set[int]:
    """Returns source lines that belong to multiline string contents."""
    content_lines: set[int] = set()
    closing_delimiter: str | None = None
    for index, line in enumerate(lines):
        if closing_delimiter is not None:
            content_lines.add(index)
            if closing_delimiter in line:
                closing_delimiter = None
            continue

        opening_match = SWIFT_MULTILINE_STRING_OPENING.search(line)
        if opening_match is None:
            continue
        hashes = opening_match.group("hashes") or ""
        candidate_closing_delimiter = f'"""{hashes}'
        remaining_line = line[opening_match.end() :]
        if candidate_closing_delimiter not in remaining_line:
            closing_delimiter = candidate_closing_delimiter
    return content_lines


def undocumented_source_declarations() -> list[str]:
    """Returns source-level declarations without leading DocC comments."""
    missing: list[str] = []
    for path in swift_source_paths():
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            if not (
                PRIVATE_DECLARATION.match(line)
                or EXTENSION_DECLARATION.match(line)
            ):
                continue
            if has_leading_doc_comment(lines, index):
                continue
            relative_path = path.relative_to(REPOSITORY_ROOT)
            missing.append(f"{relative_path}:{index + 1}")

    supporting_paths = [
        *swift_test_paths(),
        *swift_preview_tool_paths(),
        *swift_benchmark_paths(),
        *swift_comparison_benchmark_paths(),
        *swift_distribution_probe_paths(),
    ]
    for path in supporting_paths:
        lines = path.read_text(encoding="utf-8").splitlines()
        multiline_string_lines = swift_multiline_string_content_lines(lines)
        for index in range(len(lines)):
            if index in multiline_string_lines:
                continue
            if not is_supporting_swift_declaration(lines, index):
                continue
            if has_leading_doc_comment(lines, index):
                continue
            relative_path = path.relative_to(REPOSITORY_ROOT)
            missing.append(f"{relative_path}:{index + 1}")
    return missing


def undocumented_c_declarations() -> list[str]:
    """Returns authored C declarations without leading triple-slash docs."""
    missing: list[str] = []
    for path in c_header_paths():
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            if not C_DECLARATION.match(line):
                continue
            if index > 0 and lines[index - 1].strip().startswith("///"):
                continue
            relative_path = path.relative_to(REPOSITORY_ROOT)
            missing.append(f"{relative_path}:{index + 1}")
    return missing


def undocumented_c_sources() -> list[str]:
    """Returns authored C files without consecutive triple-slash summaries."""
    missing: list[str] = []
    for path in c_source_paths():
        lines = path.read_text(encoding="utf-8").splitlines()
        if (
            len(lines) >= 2
            and lines[0].startswith("///")
            and lines[1].startswith("///")
        ):
            continue
        relative_path = path.relative_to(REPOSITORY_ROOT)
        missing.append(f"{relative_path}:1")
    return missing


def validate_docc(paths: list[Path]) -> None:
    """Converts the DocC catalog and treats link warnings as failures."""
    if shutil.which("xcrun") is None:
        print("DocC conversion was skipped because xcrun is unavailable.")
        return

    with tempfile.TemporaryDirectory(
        prefix="rork-highlighter-docc-"
    ) as temporary_directory:
        temporary_path = Path(temporary_directory)
        symbol_directory = temporary_path / "symbols"
        symbol_directory.mkdir()
        for path in paths:
            shutil.copy2(path, symbol_directory / path.name)

        subprocess.run(
            [
                "xcrun",
                "docc",
                "convert",
                str(DOCC_CATALOG),
                "--additional-symbol-graph-dir",
                str(symbol_directory),
                "--output-path",
                str(temporary_path / f"{MODULE_NAME}.doccarchive"),
                "--fallback-display-name",
                MODULE_NAME,
                "--fallback-bundle-identifier",
                "com.rork.highlighter",
                "--fallback-bundle-version",
                "0.2.1",
                "--warnings-as-errors",
            ],
            cwd=REPOSITORY_ROOT,
            check=True,
        )


def main() -> int:
    """Runs documentation coverage and returns a process exit status."""
    dump_symbol_graph()
    paths = symbol_graph_paths()
    if not paths:
        print(
            f"No symbol graph was emitted for {MODULE_NAME}.",
            file=sys.stderr,
        )
        return 1

    missing_symbols = undocumented_symbols(load_symbols(paths))
    missing_source = undocumented_source_declarations()
    missing_c = undocumented_c_declarations()
    missing_c_sources = undocumented_c_sources()
    if missing_symbols or missing_source or missing_c or missing_c_sources:
        print("The following declarations need documentation:")
        for symbol in missing_symbols:
            access_level = symbol.get("accessLevel", "unknown")
            print(f"  {display_name(symbol)} [{access_level}]")
        for location in missing_source:
            print(f"  {location} [source declaration]")
        for location in missing_c:
            print(f"  {location} [authored C declaration]")
        for location in missing_c_sources:
            print(f"  {location} [authored C translation unit]")
        return 1

    validate_docc(paths)
    print(
        f"Every maintained {MODULE_NAME}, supporting tool, and authored C declaration has documentation."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
