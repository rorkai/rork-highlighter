#!/usr/bin/env python3
"""Builds the bundled Tree-sitter parsers as a static XCFramework."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, replace
from functools import cache
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Sequence
import zipfile


# The repository root owns the parser sources and their lock file.
REPOSITORY_ROOT = Path(__file__).resolve().parent.parent

# The C target is the stable module boundary consumed by generated Swift code.
MODULE_NAME = "CRorkHighlighterParsers"

# SwiftPM describes the exact translation units selected by Package.swift.
PARSER_TARGET_NAME = MODULE_NAME

# Generated build products stay under ignored SwiftPM output by default.
DEFAULT_OUTPUT_DIRECTORY = REPOSITORY_ROOT / ".build" / "parser-pack"

# The public header is shared by the source target and every binary slice.
PUBLIC_HEADER = (
    REPOSITORY_ROOT
    / "Sources"
    / MODULE_NAME
    / "include"
    / f"{MODULE_NAME}.h"
)

# The language manifest supplies every parser symbol required by the catalog.
LANGUAGE_PACK_MANIFEST = REPOSITORY_ROOT / "LanguagePack.json"

# The lock digest identifies the exact parser and query bytes behind an artifact.
LANGUAGE_PACK_LOCK = REPOSITORY_ROOT / "LanguagePack.lock.json"

# Binary redistribution retains the package and upstream license material.
PACKAGE_LICENSE = REPOSITORY_ROOT / "LICENSE"

# The notice explains which retained license belongs to each parser.
THIRD_PARTY_NOTICES = REPOSITORY_ROOT / "THIRD_PARTY_NOTICES.md"

# Exact upstream license texts remain available beside the binary artifact.
THIRD_PARTY_LICENSES = REPOSITORY_ROOT / "ThirdPartyLicenses"

# The sidecar manifest begins at one so incompatible formats fail explicitly.
ARTIFACT_SCHEMA_VERSION = 1

# Stable ZIP metadata makes checksums repeatable on one toolchain and source tree.
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)

# The generated module map preserves the source target's existing import name.
MODULE_MAP_CONTENTS = f"""module {MODULE_NAME} {{
    header \"{MODULE_NAME}.h\"
    export *
}}
"""


@dataclass(frozen=True)
class Architecture:
    """Describes one architecture and its Clang deployment target."""

    name: str
    target_triple: str


@dataclass(frozen=True)
class ParserSlice:
    """Describes one platform variant represented by an XCFramework library."""

    name: str
    sdk: str
    supported_platform: str
    supported_variant: str | None
    architectures: tuple[Architecture, ...]


@dataclass(frozen=True)
class BuiltSlice:
    """Records one completed static library and its source configuration."""

    specification: ParserSlice
    library_path: Path


@dataclass(frozen=True)
class SliceMetadata:
    """Records reproducibility metadata for one XCFramework library."""

    name: str
    sdk: str
    platform: str
    variant: str | None
    architectures: list[str]
    library_bytes: int


def slice_metadata_payload(metadata: SliceMetadata) -> dict[str, object]:
    """Returns stable camel-case JSON for one completed parser slice."""
    return {
        "name": metadata.name,
        "sdk": metadata.sdk,
        "platform": metadata.platform,
        "variant": metadata.variant,
        "architectures": metadata.architectures,
        "libraryBytes": metadata.library_bytes,
    }


# The matrix matches every Apple platform declared by Package.swift.
PARSER_SLICES = (
    ParserSlice(
        name="macos",
        sdk="macosx",
        supported_platform="macos",
        supported_variant=None,
        architectures=(
            Architecture("arm64", "arm64-apple-macos13.0"),
            Architecture("x86_64", "x86_64-apple-macos13.0"),
        ),
    ),
    ParserSlice(
        name="ios",
        sdk="iphoneos",
        supported_platform="ios",
        supported_variant=None,
        architectures=(Architecture("arm64", "arm64-apple-ios16.0"),),
    ),
    ParserSlice(
        name="ios-simulator",
        sdk="iphonesimulator",
        supported_platform="ios",
        supported_variant="simulator",
        architectures=(
            Architecture("arm64", "arm64-apple-ios16.0-simulator"),
            Architecture("x86_64", "x86_64-apple-ios16.0-simulator"),
        ),
    ),
    ParserSlice(
        name="maccatalyst",
        sdk="macosx",
        supported_platform="ios",
        supported_variant="maccatalyst",
        architectures=(
            Architecture("arm64", "arm64-apple-ios16.0-macabi"),
            Architecture("x86_64", "x86_64-apple-ios16.0-macabi"),
        ),
    ),
    ParserSlice(
        name="tvos",
        sdk="appletvos",
        supported_platform="tvos",
        supported_variant=None,
        architectures=(Architecture("arm64", "arm64-apple-tvos16.0"),),
    ),
    ParserSlice(
        name="tvos-simulator",
        sdk="appletvsimulator",
        supported_platform="tvos",
        supported_variant="simulator",
        architectures=(
            Architecture("arm64", "arm64-apple-tvos16.0-simulator"),
            Architecture("x86_64", "x86_64-apple-tvos16.0-simulator"),
        ),
    ),
    ParserSlice(
        name="watchos",
        sdk="watchos",
        supported_platform="watchos",
        supported_variant=None,
        architectures=(
            Architecture("arm64_32", "arm64_32-apple-watchos9.0"),
        ),
    ),
    ParserSlice(
        name="watchos-simulator",
        sdk="watchsimulator",
        supported_platform="watchos",
        supported_variant="simulator",
        architectures=(
            Architecture("arm64", "arm64-apple-watchos9.0-simulator"),
            Architecture("x86_64", "x86_64-apple-watchos9.0-simulator"),
        ),
    ),
    ParserSlice(
        name="visionos",
        sdk="xros",
        supported_platform="xros",
        supported_variant=None,
        architectures=(Architecture("arm64", "arm64-apple-xros1.0"),),
    ),
    ParserSlice(
        name="visionos-simulator",
        sdk="xrsimulator",
        supported_platform="xros",
        supported_variant="simulator",
        architectures=(
            Architecture("arm64", "arm64-apple-xros1.0-simulator"),
            Architecture("x86_64", "x86_64-apple-xros1.0-simulator"),
        ),
    ),
)


def parse_arguments() -> argparse.Namespace:
    """Parses command-line options for artifact generation."""
    parser = argparse.ArgumentParser(
        description=(
            "Build the locked parser sources as a static Apple XCFramework."
        )
    )
    parser.add_argument(
        "--output-directory",
        type=Path,
        default=DEFAULT_OUTPUT_DIRECTORY,
        help="Directory that receives the XCFramework, ZIP, and metadata.",
    )
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument(
        "--slice",
        action="append",
        choices=[item.name for item in PARSER_SLICES],
        help="Platform slice to build. Repeat the option to select more than one.",
    )
    selection.add_argument(
        "--host-only",
        action="store_true",
        help="Build only the current macOS architecture for a fast smoke check.",
    )
    parser.add_argument(
        "--jobs",
        type=int,
        default=min(8, os.cpu_count() or 1),
        help="Maximum parser translation units compiled concurrently.",
    )
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        help="Permit artifacts from a modified source tree and record that state.",
    )
    parser.add_argument(
        "--skip-smoke-test",
        action="store_true",
        help="Skip the local SwiftPM consumer build for a host-compatible slice.",
    )
    return parser.parse_args()


def run_command(
    command: Sequence[str],
    *,
    cwd: Path = REPOSITORY_ROOT,
    environment: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Runs a command and captures output for concise failure diagnostics."""
    command_environment = None
    if environment is not None:
        command_environment = os.environ.copy()
        command_environment.update(environment)
    return subprocess.run(
        list(command),
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
        env=command_environment,
    )


@cache
def xcrun_tool(tool: str, sdk: str | None = None) -> str:
    """Returns the selected Xcode command-line tool path."""
    command = ["xcrun"]
    if sdk is not None:
        command.extend(["--sdk", sdk])
    command.extend(["--find", tool])
    return run_command(command).stdout.strip()


@cache
def sdk_path(sdk: str) -> str:
    """Returns the SDK root used by one parser slice."""
    return run_command(
        ["xcrun", "--sdk", sdk, "--show-sdk-path"]
    ).stdout.strip()


def select_slices(
    requested_names: Sequence[str] | None,
    host_only: bool,
    host_architecture: str | None = None,
) -> tuple[ParserSlice, ...]:
    """Returns the platform matrix requested by the current invocation."""
    if host_only:
        architecture_name = host_architecture or platform.machine()
        macos = next(item for item in PARSER_SLICES if item.name == "macos")
        matching = tuple(
            architecture
            for architecture in macos.architectures
            if architecture.name == architecture_name
        )
        if not matching:
            raise ValueError(
                f"The host architecture {architecture_name} is unsupported."
            )
        return (replace(macos, architectures=matching),)

    if requested_names is None:
        return PARSER_SLICES

    requested = set(requested_names)
    return tuple(item for item in PARSER_SLICES if item.name in requested)


def validate_language_pack() -> None:
    """Verifies every vendored parser byte before compiling an artifact."""
    run_command([sys.executable, "Scripts/vendor_languages.py"])


def parser_sources() -> list[Path]:
    """Returns the exact C translation units selected by Package.swift."""
    description = json.loads(
        run_command(
            ["swift", "package", "describe", "--type", "json"]
        ).stdout
    )
    try:
        target = next(
            item
            for item in description["targets"]
            if item["name"] == PARSER_TARGET_NAME
        )
    except (KeyError, StopIteration) as error:
        raise ValueError(
            f"Package.swift does not describe {PARSER_TARGET_NAME}."
        ) from error

    target_path = Path(target["path"])
    if not target_path.is_absolute():
        target_path = REPOSITORY_ROOT / target_path
    sources = sorted(
        (target_path / relative_path).resolve()
        for relative_path in target.get("sources", [])
        if Path(relative_path).suffix == ".c"
    )
    if not sources:
        raise ValueError("The parser target contains no C translation units.")
    missing = [path for path in sources if not path.is_file()]
    if missing:
        raise FileNotFoundError(
            f"The parser source {missing[0]} does not exist."
        )
    return sources


def parser_entry_points() -> tuple[str, ...]:
    """Returns every exported parser constructor required by the catalog."""
    manifest = json.loads(LANGUAGE_PACK_MANIFEST.read_text(encoding="utf-8"))
    try:
        entry_points = tuple(
            language["entryPoint"] for language in manifest["languages"]
        )
    except (KeyError, TypeError) as error:
        raise ValueError(
            "LanguagePack.json does not contain parser entry points."
        ) from error
    if not entry_points or len(set(entry_points)) != len(entry_points):
        raise ValueError("Parser entry points must be nonempty and unique.")
    return entry_points


def repository_revision() -> str:
    """Returns the Git revision used to produce the artifact."""
    return run_command(["git", "rev-parse", "HEAD"]).stdout.strip()


def repository_is_dirty() -> bool:
    """Reports whether tracked or untracked source changes are present."""
    return bool(run_command(["git", "status", "--porcelain"]).stdout.strip())


def file_sha256(path: Path) -> str:
    """Returns the lowercase SHA-256 digest for one file."""
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_tree_sha256(sources: Sequence[Path]) -> str:
    """Returns a path-sensitive digest for every compiled translation unit."""
    digest = hashlib.sha256()
    for source in sources:
        relative_path = source.relative_to(REPOSITORY_ROOT).as_posix()
        digest.update(relative_path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(bytes.fromhex(file_sha256(source)))
    return digest.hexdigest()


def object_path(
    source: Path,
    object_directory: Path,
) -> Path:
    """Returns a collision-free object path for one parser source."""
    relative_path = source.relative_to(
        REPOSITORY_ROOT / "Sources" / MODULE_NAME
    )
    return object_directory / Path(f"{relative_path.as_posix()}.o")


def compile_command(
    source: Path,
    destination: Path,
    architecture: Architecture,
    sdk: str,
) -> list[str]:
    """Returns the deterministic Clang invocation for one parser source."""
    return [
        xcrun_tool("clang", sdk),
        "-target",
        architecture.target_triple,
        "-isysroot",
        sdk_path(sdk),
        "-std=c11",
        "-O2",
        "-DNDEBUG",
        "-fPIC",
        "-fno-common",
        "-c",
        str(source),
        "-o",
        str(destination),
    ]


def compile_source(
    source: Path,
    destination: Path,
    architecture: Architecture,
    sdk: str,
) -> None:
    """Compiles one parser source into its architecture-specific object."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    run_command(compile_command(source, destination, architecture, sdk))


def build_architecture_library(
    specification: ParserSlice,
    architecture: Architecture,
    sources: Sequence[Path],
    scratch_directory: Path,
    jobs: int,
) -> Path:
    """Compiles and archives every parser for one target architecture."""
    print(
        f"Compiling {specification.name}/{architecture.name} "
        f"from {len(sources)} translation units.",
        file=sys.stderr,
    )
    architecture_directory = (
        scratch_directory / specification.name / architecture.name
    )
    object_directory = architecture_directory / "objects"
    destinations = [
        object_path(source, object_directory) for source in sources
    ]
    with ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = [
            executor.submit(
                compile_source,
                source,
                destination,
                architecture,
                specification.sdk,
            )
            for source, destination in zip(sources, destinations, strict=True)
        ]
        for future in as_completed(futures):
            future.result()

    library_path = architecture_directory / f"lib{MODULE_NAME}.a"
    run_command(
        [
            xcrun_tool("ar"),
            "rcs",
            str(library_path),
            *(str(path) for path in destinations),
        ],
        environment={"ZERO_AR_DATE": "1"},
    )
    return library_path


def combine_architecture_libraries(
    specification: ParserSlice,
    architecture_libraries: Sequence[Path],
    scratch_directory: Path,
) -> Path:
    """Returns one static library containing every architecture in a slice."""
    slice_directory = scratch_directory / specification.name / "combined"
    slice_directory.mkdir(parents=True, exist_ok=True)
    library_path = slice_directory / f"lib{MODULE_NAME}.a"
    if len(architecture_libraries) == 1:
        shutil.copyfile(architecture_libraries[0], library_path)
    else:
        run_command(
            [
                "xcrun",
                "lipo",
                "-create",
                *(str(path) for path in architecture_libraries),
                "-output",
                str(library_path),
            ]
        )

    architectures = set(
        run_command(
            ["xcrun", "lipo", "-archs", str(library_path)]
        ).stdout.split()
    )
    expected = {
        architecture.name for architecture in specification.architectures
    }
    if architectures != expected:
        raise ValueError(
            f"The {specification.name} library contains {architectures}, "
            f"but expected {expected}."
        )
    return library_path


def build_slice(
    specification: ParserSlice,
    sources: Sequence[Path],
    scratch_directory: Path,
    jobs: int,
) -> BuiltSlice:
    """Builds one complete XCFramework platform slice."""
    architecture_libraries = [
        build_architecture_library(
            specification,
            architecture,
            sources,
            scratch_directory,
            jobs,
        )
        for architecture in specification.architectures
    ]
    return BuiltSlice(
        specification=specification,
        library_path=combine_architecture_libraries(
            specification,
            architecture_libraries,
            scratch_directory,
        ),
    )


def prepare_headers(scratch_directory: Path) -> Path:
    """Creates the public C module consumed by SwiftPM binary targets."""
    headers_directory = scratch_directory / "Headers"
    headers_directory.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(
        PUBLIC_HEADER,
        headers_directory / PUBLIC_HEADER.name,
    )
    (headers_directory / "module.modulemap").write_text(
        MODULE_MAP_CONTENTS,
        encoding="utf-8",
    )
    return headers_directory


def create_xcframework(
    built_slices: Sequence[BuiltSlice],
    headers_directory: Path,
    output_path: Path,
) -> None:
    """Combines static parser libraries into one XCFramework directory."""
    if output_path.exists():
        shutil.rmtree(output_path)
    command = ["xcodebuild", "-create-xcframework"]
    for built_slice in built_slices:
        command.extend(
            [
                "-library",
                str(built_slice.library_path),
                "-headers",
                str(headers_directory),
            ]
        )
    command.extend(["-output", str(output_path)])
    run_command(command)


def normalize_xcframework_info_plist(xcframework_path: Path) -> None:
    """Canonicalizes generated slice ordering for byte-stable archives."""
    info_path = xcframework_path / "Info.plist"
    with info_path.open("rb") as plist_file:
        plist = plistlib.load(plist_file)
    libraries = plist.get("AvailableLibraries")
    if not isinstance(libraries, list) or not all(
        isinstance(item, dict)
        and isinstance(item.get("LibraryIdentifier"), str)
        for item in libraries
    ):
        raise ValueError("The XCFramework has malformed library metadata.")
    plist["AvailableLibraries"] = sorted(
        libraries,
        key=lambda item: item["LibraryIdentifier"],
    )
    with info_path.open("wb") as plist_file:
        plistlib.dump(
            plist,
            plist_file,
            fmt=plistlib.FMT_XML,
            sort_keys=True,
        )


def copy_license_materials(xcframework_path: Path) -> None:
    """Retains package and parser licenses inside the binary distribution."""
    shutil.copyfile(PACKAGE_LICENSE, xcframework_path / PACKAGE_LICENSE.name)
    shutil.copyfile(
        THIRD_PARTY_NOTICES,
        xcframework_path / THIRD_PARTY_NOTICES.name,
    )
    licenses_destination = xcframework_path / THIRD_PARTY_LICENSES.name
    if licenses_destination.exists():
        shutil.rmtree(licenses_destination)
    shutil.copytree(THIRD_PARTY_LICENSES, licenses_destination)


def remove_existing_output(path: Path) -> None:
    """Removes one exact stale output before a new artifact build begins."""
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def available_libraries(xcframework_path: Path) -> list[dict[str, object]]:
    """Returns the XCFramework library descriptions from Info.plist."""
    with (xcframework_path / "Info.plist").open("rb") as plist_file:
        plist = plistlib.load(plist_file)
    libraries = plist.get("AvailableLibraries")
    if not isinstance(libraries, list):
        raise ValueError("The XCFramework has no AvailableLibraries array.")
    return libraries


def validate_xcframework_structure(
    xcframework_path: Path,
    specifications: Sequence[ParserSlice],
) -> list[Path]:
    """Validates platform coverage and returns every static library path."""
    libraries = available_libraries(xcframework_path)
    actual_configurations: set[
        tuple[str, str | None, tuple[str, ...]]
    ] = set()
    library_paths: list[Path] = []
    for library in libraries:
        platform_name = library.get("SupportedPlatform")
        variant = library.get("SupportedPlatformVariant")
        architectures = library.get("SupportedArchitectures")
        identifier = library.get("LibraryIdentifier")
        library_name = library.get("LibraryPath")
        headers_name = library.get("HeadersPath")
        if (
            not isinstance(platform_name, str)
            or (variant is not None and not isinstance(variant, str))
            or not isinstance(architectures, list)
            or not all(isinstance(item, str) for item in architectures)
            or not isinstance(identifier, str)
            or not isinstance(library_name, str)
            or not isinstance(headers_name, str)
        ):
            raise ValueError("The XCFramework contains malformed slice metadata.")
        actual_configurations.add(
            (platform_name, variant, tuple(sorted(architectures)))
        )
        slice_directory = xcframework_path / identifier
        library_path = slice_directory / library_name
        headers_path = slice_directory / headers_name
        if not library_path.is_file():
            raise FileNotFoundError(
                f"The XCFramework library {library_path} is missing."
            )
        if not (headers_path / PUBLIC_HEADER.name).is_file():
            raise FileNotFoundError(
                f"The public header is missing from {headers_path}."
            )
        if not (headers_path / "module.modulemap").is_file():
            raise FileNotFoundError(
                f"The module map is missing from {headers_path}."
            )
        library_paths.append(library_path)

    expected_configurations = {
        (
            specification.supported_platform,
            specification.supported_variant,
            tuple(
                sorted(
                    architecture.name
                    for architecture in specification.architectures
                )
            ),
        )
        for specification in specifications
    }
    if actual_configurations != expected_configurations:
        raise ValueError(
            "The XCFramework platform matrix does not match the requested slices."
        )
    return library_paths


def exported_symbols(library_path: Path) -> set[str]:
    """Returns global parser-style symbols exported by one static library."""
    output = run_command(
        ["xcrun", "nm", "-gU", str(library_path)]
    ).stdout
    symbols: set[str] = set()
    pattern = re.compile(r"_?(tree_sitter_[A-Za-z0-9_]+)$")
    for line in output.splitlines():
        match = pattern.search(line)
        if match is not None:
            symbols.add(match.group(1))
    return symbols


def validate_exported_symbols(
    library_paths: Sequence[Path],
    entry_points: Sequence[str],
) -> None:
    """Ensures every binary slice exports all catalog parser constructors."""
    expected = set(entry_points)
    for library_path in library_paths:
        missing = expected - exported_symbols(library_path)
        if missing:
            missing_list = ", ".join(sorted(missing))
            raise ValueError(
                f"The library {library_path} is missing {missing_list}."
            )


def validate_license_materials(xcframework_path: Path) -> None:
    """Ensures binary redistribution includes every retained license file."""
    required_paths = [
        xcframework_path / PACKAGE_LICENSE.name,
        xcframework_path / THIRD_PARTY_NOTICES.name,
    ]
    required_paths.extend(
        xcframework_path
        / THIRD_PARTY_LICENSES.name
        / path.relative_to(THIRD_PARTY_LICENSES)
        for path in THIRD_PARTY_LICENSES.rglob("*")
        if path.is_file()
    )
    missing = [path for path in required_paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(
            f"The binary distribution license {missing[0]} is missing."
        )


def smoke_test_source(entry_points: Sequence[str]) -> str:
    """Returns a Swift program that links and loads every parser constructor."""
    calls = ",\n    ".join(f"{entry_point}()" for entry_point in entry_points)
    return f"""import {MODULE_NAME}

let languages = [
    {calls}
]
precondition(languages.allSatisfy {{ $0 != nil }})
print(languages.count)
"""


def run_swiftpm_smoke_test(
    xcframework_path: Path,
    entry_points: Sequence[str],
    scratch_directory: Path,
) -> None:
    """Builds a local SwiftPM consumer against the generated binary target."""
    smoke_directory = scratch_directory / "smoke-package"
    source_directory = smoke_directory / "Sources" / "ParserPackSmoke"
    source_directory.mkdir(parents=True, exist_ok=True)
    linked_artifact = smoke_directory / xcframework_path.name
    linked_artifact.symlink_to(xcframework_path, target_is_directory=True)
    (smoke_directory / "Package.swift").write_text(
        f"""// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ParserPackSmoke",
    platforms: [.macOS(.v13)],
    targets: [
        .binaryTarget(
            name: "{MODULE_NAME}",
            path: "{xcframework_path.name}"
        ),
        .executableTarget(
            name: "ParserPackSmoke",
            dependencies: ["{MODULE_NAME}"]
        ),
    ]
)
""",
        encoding="utf-8",
    )
    (source_directory / "main.swift").write_text(
        smoke_test_source(entry_points),
        encoding="utf-8",
    )
    result = run_command(
        [
            "swift",
            "run",
            "--package-path",
            str(smoke_directory),
            "--scratch-path",
            str(scratch_directory / "smoke-build"),
            "-c",
            "release",
            "ParserPackSmoke",
        ]
    )
    if result.stdout.strip() != str(len(entry_points)):
        raise ValueError("The binary parser smoke test returned an invalid count.")


def write_deterministic_zip(source_directory: Path, archive_path: Path) -> None:
    """Writes one stable ZIP whose root contains the XCFramework directory."""
    if archive_path.exists():
        archive_path.unlink()
    paths = [source_directory]
    paths.extend(sorted(source_directory.rglob("*")))
    with zipfile.ZipFile(
        archive_path,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for path in paths:
            relative_path = path.relative_to(source_directory.parent)
            archive_name = relative_path.as_posix()
            if path.is_dir():
                archive_name += "/"
            information = zipfile.ZipInfo(archive_name, ZIP_TIMESTAMP)
            information.create_system = 3
            information.compress_type = zipfile.ZIP_DEFLATED
            if path.is_dir():
                information.external_attr = (0o40755 << 16) | 0x10
                archive.writestr(information, b"")
                continue
            information.external_attr = 0o100644 << 16
            with path.open("rb") as source_file:
                with archive.open(information, mode="w") as archived_file:
                    shutil.copyfileobj(
                        source_file,
                        archived_file,
                        length=1024 * 1024,
                    )


def swiftpm_checksum(archive_path: Path) -> str:
    """Returns SwiftPM's checksum for one remote binary-target archive."""
    return run_command(
        ["swift", "package", "compute-checksum", str(archive_path)]
    ).stdout.strip()


def toolchain_description() -> dict[str, str]:
    """Returns the Xcode, Clang, and Swift versions used for compilation."""
    return {
        "xcode": " ".join(
            run_command(["xcodebuild", "-version"]).stdout.splitlines()
        ),
        "clang": run_command(
            [xcrun_tool("clang"), "--version"]
        ).stdout.splitlines()[0],
        "swift": " ".join(
            run_command(["swift", "--version"]).stdout.splitlines()
        ),
    }


def artifact_metadata(
    *,
    revision: str,
    dirty: bool,
    sources: Sequence[Path],
    built_slices: Sequence[BuiltSlice],
    archive_path: Path,
    archive_checksum: str,
) -> dict[str, object]:
    """Returns the machine-readable provenance for a completed parser pack."""
    slices = [
        SliceMetadata(
            name=built_slice.specification.name,
            sdk=built_slice.specification.sdk,
            platform=built_slice.specification.supported_platform,
            variant=built_slice.specification.supported_variant,
            architectures=[
                architecture.name
                for architecture in built_slice.specification.architectures
            ],
            library_bytes=built_slice.library_path.stat().st_size,
        )
        for built_slice in built_slices
    ]
    return {
        "schemaVersion": ARTIFACT_SCHEMA_VERSION,
        "moduleName": MODULE_NAME,
        "revision": revision,
        "workingTreeDirty": dirty,
        "languagePackLockSHA256": file_sha256(LANGUAGE_PACK_LOCK),
        "compiledSourceSHA256": source_tree_sha256(sources),
        "compiledSourceFiles": len(sources),
        "compiledSourceBytes": sum(path.stat().st_size for path in sources),
        "archiveFileName": archive_path.name,
        "archiveBytes": archive_path.stat().st_size,
        "archiveSHA256": file_sha256(archive_path),
        "swiftPMChecksum": archive_checksum,
        "toolchain": toolchain_description(),
        "slices": [slice_metadata_payload(item) for item in slices],
    }


def write_artifact_metadata(
    metadata: dict[str, object],
    output_path: Path,
) -> None:
    """Writes stable JSON provenance beside the binary archive."""
    output_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def build_artifact(arguments: argparse.Namespace) -> dict[str, object]:
    """Builds, validates, archives, and describes the requested parser pack."""
    if platform.system() != "Darwin":
        raise OSError("Parser XCFrameworks require macOS and Xcode.")
    if arguments.jobs < 1:
        raise ValueError("The job count must be positive.")

    dirty = repository_is_dirty()
    if dirty and not arguments.allow_dirty:
        raise ValueError(
            "The source tree is dirty. Commit changes or pass --allow-dirty."
        )

    validate_language_pack()
    sources = parser_sources()
    entry_points = parser_entry_points()
    specifications = select_slices(arguments.slice, arguments.host_only)
    output_directory = arguments.output_directory.resolve()
    output_directory.mkdir(parents=True, exist_ok=True)
    xcframework_path = output_directory / f"{MODULE_NAME}.xcframework"
    archive_path = output_directory / f"{MODULE_NAME}.xcframework.zip"
    metadata_path = output_directory / f"{MODULE_NAME}.artifact.json"
    for output_path in (xcframework_path, archive_path, metadata_path):
        remove_existing_output(output_path)

    with tempfile.TemporaryDirectory(
        prefix="intermediates-",
        dir=output_directory,
    ) as temporary_directory:
        scratch_directory = Path(temporary_directory)
        headers_directory = prepare_headers(scratch_directory)
        built_slices = [
            build_slice(
                specification,
                sources,
                scratch_directory,
                arguments.jobs,
            )
            for specification in specifications
        ]
        create_xcframework(
            built_slices,
            headers_directory,
            xcframework_path,
        )
        normalize_xcframework_info_plist(xcframework_path)
        copy_license_materials(xcframework_path)
        library_paths = validate_xcframework_structure(
            xcframework_path,
            specifications,
        )
        validate_exported_symbols(library_paths, entry_points)
        validate_license_materials(xcframework_path)
        has_host_slice = any(
            specification.name == "macos"
            and platform.machine()
            in {
                architecture.name
                for architecture in specification.architectures
            }
            for specification in specifications
        )
        if has_host_slice and not arguments.skip_smoke_test:
            print("Building the local SwiftPM binary consumer.", file=sys.stderr)
            run_swiftpm_smoke_test(
                xcframework_path,
                entry_points,
                scratch_directory,
            )

        write_deterministic_zip(xcframework_path, archive_path)
        checksum = swiftpm_checksum(archive_path)
        archive_digest = file_sha256(archive_path)
        if checksum != archive_digest:
            raise ValueError(
                "SwiftPM and SHA-256 disagree about the archive checksum."
            )
        metadata = artifact_metadata(
            revision=repository_revision(),
            dirty=dirty,
            sources=sources,
            built_slices=built_slices,
            archive_path=archive_path,
            archive_checksum=checksum,
        )
        write_artifact_metadata(metadata, metadata_path)
        return metadata


def main() -> int:
    """Builds the requested parser pack and prints its artifact metadata."""
    arguments = parse_arguments()
    try:
        metadata = build_artifact(arguments)
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout, file=sys.stderr)
        if error.stderr:
            print(error.stderr, file=sys.stderr)
        return error.returncode
    except (FileNotFoundError, OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    print(json.dumps(metadata, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
