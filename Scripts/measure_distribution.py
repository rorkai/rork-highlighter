#!/usr/bin/env python3
"""Measures clean release builds and the bundled distribution footprint."""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import platform
import subprocess
import sys
import time
from typing import Sequence


# The repository root contains the package and private probe.
REPOSITORY_ROOT = Path(__file__).resolve().parent.parent

# The probe package links every bundled parser through the standard catalog.
PROBE_PACKAGE = REPOSITORY_ROOT / "Tools" / "DistributionProbe"

# The default scratch directory stays inside ignored SwiftPM output.
DEFAULT_SCRATCH_PATH = REPOSITORY_ROOT / ".build" / "distribution-metrics"

# Generated parser sources contribute most of the source distribution size.
PARSER_SOURCE_DIRECTORY = (
    REPOSITORY_ROOT / "Sources" / "CRorkHighlighterParsers" / "languages"
)

# Query resources ship beside the linked library on every supported platform.
QUERY_SOURCE_DIRECTORY = (
    REPOSITORY_ROOT
    / "Sources"
    / "RorkHighlighter"
    / "Resources"
    / "Languages"
)


@dataclass(frozen=True)
class FileMeasurements:
    """Holds aggregate counts for a selected collection of files."""

    file_count: int
    byte_count: int
    line_count: int


@dataclass(frozen=True)
class DistributionMeasurements:
    """Holds one machine-readable distribution measurement result."""

    schema_version: int
    revision: str
    working_tree_dirty: bool
    platform: str
    architecture: str
    swift_version: str
    build_seconds: float
    parser_source_files: int
    parser_source_bytes: int
    parser_source_lines: int
    query_source_files: int
    query_source_bytes: int
    parser_object_bytes: int
    executable_bytes: int
    resource_bundle_bytes: int
    linked_product_bytes: int


def parse_arguments() -> argparse.Namespace:
    """Parses command-line options for the measurement run."""
    parser = argparse.ArgumentParser(
        description=(
            "Measure a clean release build and its bundled parser footprint."
        )
    )
    parser.add_argument(
        "--scratch-path",
        type=Path,
        default=DEFAULT_SCRATCH_PATH,
        help="SwiftPM scratch directory used for the clean probe build.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional path that also receives the JSON result.",
    )
    return parser.parse_args()


def run_command(
    command: Sequence[str],
    *,
    cwd: Path = REPOSITORY_ROOT,
) -> subprocess.CompletedProcess[str]:
    """Runs a command and captures text output for clean JSON reporting."""
    return subprocess.run(
        list(command),
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    )


def measure_files(
    root: Path,
    suffixes: frozenset[str] | None = None,
) -> FileMeasurements:
    """Counts files, bytes, and text lines beneath a directory."""
    paths = sorted(
        path
        for path in root.rglob("*")
        if path.is_file()
        and (suffixes is None or path.suffix in suffixes)
    )
    byte_count = 0
    line_count = 0
    for path in paths:
        contents = path.read_bytes()
        byte_count += len(contents)
        line_count += contents.count(b"\n")
        if contents and not contents.endswith(b"\n"):
            line_count += 1
    return FileMeasurements(
        file_count=len(paths),
        byte_count=byte_count,
        line_count=line_count,
    )


def parser_object_bytes(scratch_path: Path) -> int:
    """Returns the combined size of compiled parser object files."""
    return sum(
        path.stat().st_size
        for path in scratch_path.rglob("*.o")
        if "CRorkHighlighterParsers.build" in path.parts
    )


def resource_bundle_bytes(binary_directory: Path) -> int:
    """Returns the size of Rork Highlighter resource bundles beside a probe."""
    return sum(
        measure_files(path).byte_count
        for path in binary_directory.glob("*RorkHighlighter*.bundle")
        if path.is_dir()
    )


def swift_package_command(
    scratch_path: Path,
    subcommand: str,
    *arguments: str,
) -> list[str]:
    """Builds a Swift package command scoped to the private probe."""
    return [
        "swift",
        "package",
        "--package-path",
        str(PROBE_PACKAGE),
        "--scratch-path",
        str(scratch_path),
        subcommand,
        *arguments,
    ]


def swift_build_command(
    scratch_path: Path,
    *arguments: str,
) -> list[str]:
    """Builds a Swift build command scoped to the private probe."""
    return [
        "swift",
        "build",
        "--package-path",
        str(PROBE_PACKAGE),
        "--scratch-path",
        str(scratch_path),
        *arguments,
    ]


def clean_build(scratch_path: Path) -> tuple[float, Path]:
    """Resolves dependencies, cleans products, and times a release build."""
    print("Resolving probe dependencies.", file=sys.stderr)
    run_command(swift_package_command(scratch_path, "resolve"))
    print("Cleaning previous probe products.", file=sys.stderr)
    run_command(swift_package_command(scratch_path, "clean"))

    print("Building the release distribution probe.", file=sys.stderr)
    start = time.perf_counter()
    run_command(
        swift_build_command(
            scratch_path,
            "-c",
            "release",
            "--product",
            "DistributionProbe",
        )
    )
    elapsed = time.perf_counter() - start
    binary_directory = Path(
        run_command(
            swift_build_command(
                scratch_path,
                "-c",
                "release",
                "--show-bin-path",
            )
        ).stdout.strip()
    )
    return elapsed, binary_directory


def collect_measurements(scratch_path: Path) -> DistributionMeasurements:
    """Runs the clean probe and collects source, object, and product sizes."""
    elapsed, binary_directory = clean_build(scratch_path)
    executable = binary_directory / "DistributionProbe"
    if not executable.is_file():
        raise FileNotFoundError(
            f"The distribution probe was not found at {executable}."
        )

    probe_output = run_command([str(executable)]).stdout.strip()
    if not probe_output.isdigit() or int(probe_output) <= 0:
        raise RuntimeError(
            "The distribution probe did not produce highlighted spans."
        )

    parser_sources = measure_files(
        PARSER_SOURCE_DIRECTORY,
        frozenset({".c", ".h"}),
    )
    query_sources = measure_files(
        QUERY_SOURCE_DIRECTORY,
        frozenset({".scm"}),
    )
    executable_size = executable.stat().st_size
    bundled_resources = resource_bundle_bytes(binary_directory)
    swift_version = run_command(["swift", "--version"]).stdout
    revision = run_command(["git", "rev-parse", "HEAD"]).stdout.strip()
    working_tree_dirty = bool(
        run_command(["git", "status", "--porcelain"]).stdout.strip()
    )

    return DistributionMeasurements(
        schema_version=1,
        revision=revision,
        working_tree_dirty=working_tree_dirty,
        platform=platform.system(),
        architecture=platform.machine(),
        swift_version=" ".join(swift_version.splitlines()),
        build_seconds=round(elapsed, 3),
        parser_source_files=parser_sources.file_count,
        parser_source_bytes=parser_sources.byte_count,
        parser_source_lines=parser_sources.line_count,
        query_source_files=query_sources.file_count,
        query_source_bytes=query_sources.byte_count,
        parser_object_bytes=parser_object_bytes(scratch_path),
        executable_bytes=executable_size,
        resource_bundle_bytes=bundled_resources,
        linked_product_bytes=executable_size + bundled_resources,
    )


def main() -> int:
    """Measures the distribution and writes stable, sorted JSON."""
    arguments = parse_arguments()
    scratch_path = arguments.scratch_path.resolve()
    try:
        measurements = collect_measurements(scratch_path)
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout, file=sys.stderr)
        if error.stderr:
            print(error.stderr, file=sys.stderr)
        return error.returncode
    except (FileNotFoundError, RuntimeError) as error:
        print(error, file=sys.stderr)
        return 1

    output = json.dumps(
        asdict(measurements),
        indent=2,
        sort_keys=True,
    ) + "\n"
    print(output, end="")
    if arguments.output is not None:
        output_path = arguments.output.resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(output, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
