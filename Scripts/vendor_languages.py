#!/usr/bin/env python3
"""Updates and verifies the generated common language pack."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import Any


# The repository root contains the manifest and every managed output.
REPOSITORY_ROOT = Path(__file__).resolve().parent.parent

# The manifest records exact upstream revisions and language metadata.
MANIFEST_PATH = REPOSITORY_ROOT / "LanguagePack.json"

# The lock records the bytes installed from the pinned upstream revisions.
LOCK_PATH = REPOSITORY_ROOT / "LanguagePack.lock.json"

# The notices document attributes every source distributed in the pack.
NOTICES_PATH = REPOSITORY_ROOT / "THIRD_PARTY_NOTICES.md"

# Generated parser sources are copied into the shared Clang target.
PARSER_SOURCES_PATH = Path("Sources/CRorkHighlighterParsers/languages")

# The generated header exposes every parser entry point to Swift.
GENERATED_HEADER_PATH = Path(
    "Sources/CRorkHighlighterParsers/include/CRorkHighlighterParsers.h"
)

# The generated Swift source constructs the standard language catalog.
GENERATED_SWIFT_PATH = Path(
    "Sources/RorkHighlighter/BundledLanguages.generated.swift"
)

# Bundled Tree-sitter queries are copied as SwiftPM resources.
QUERY_RESOURCES_PATH = Path("Sources/RorkHighlighter/Resources/Languages")

# Retained upstream license texts accompany the distributed parser sources.
RETAINED_LICENSES_PATH = Path("ThirdPartyLicenses")

# These paths are replaced together when the language pack is updated.
MANAGED_PATHS = (
    PARSER_SOURCES_PATH,
    GENERATED_HEADER_PATH,
    GENERATED_SWIFT_PATH,
    QUERY_RESOURCES_PATH,
    RETAINED_LICENSES_PATH,
)

# Repository fetches fail instead of hanging indefinitely.
GIT_FETCH_TIMEOUT_SECONDS = 300

# Official packs accept only licenses that allow commercial redistribution.
PERMISSIVE_LICENSES = {
    "0BSD",
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "MIT",
    "Unlicense",
    "Zlib",
}

# Query files use these roles when constructing Tree-sitter configurations.
QUERY_KINDS = {"highlights", "injections", "locals"}

# Finder metadata is not part of the generated language pack.
IGNORED_MANAGED_FILENAMES = {".DS_Store"}


def parse_arguments() -> argparse.Namespace:
    """Parses the update mode requested by the maintainer."""
    parser = argparse.ArgumentParser(
        description="Updates or verifies the bundled Tree-sitter languages."
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="Downloads pinned sources and replaces the managed language pack.",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    """Loads a UTF-8 JSON object from a repository file."""
    with path.open(encoding="utf-8") as file:
        value = json.load(file)
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} must contain a JSON object.")
    return value


def load_manifest() -> dict[str, Any]:
    """Loads and validates the language pack manifest."""
    manifest = load_json(MANIFEST_PATH)
    if manifest.get("schemaVersion") != 1:
        raise ValueError("LanguagePack.json uses an unsupported schema version.")

    repositories = manifest.get("repositories")
    languages = manifest.get("languages")
    if not isinstance(repositories, dict) or not isinstance(languages, list):
        raise ValueError("LanguagePack.json is missing repositories or languages.")

    validate_repositories(repositories)
    validate_languages(repositories, languages)
    return manifest


def validate_repositories(repositories: dict[str, Any]) -> None:
    """Rejects incomplete repositories and licenses unsuitable for a pack."""
    required_fields = {
        "name",
        "url",
        "reference",
        "revision",
        "license",
        "licenseFile",
    }
    for identifier, repository in repositories.items():
        if not isinstance(repository, dict):
            raise ValueError(f"Repository '{identifier}' must be an object.")
        missing_fields = required_fields.difference(repository)
        if missing_fields:
            missing = ", ".join(sorted(missing_fields))
            raise ValueError(f"Repository '{identifier}' is missing {missing}.")
        if repository["license"] not in PERMISSIVE_LICENSES:
            raise ValueError(
                f"Repository '{identifier}' does not use an approved license."
            )
        revision = repository["revision"]
        if (
            not isinstance(revision, str)
            or len(revision) != 40
            or any(character not in "0123456789abcdef" for character in revision)
        ):
            raise ValueError(
                f"Repository '{identifier}' must use a full lowercase revision."
            )


def validate_languages(
    repositories: dict[str, Any],
    languages: list[dict[str, Any]],
) -> None:
    """Rejects ambiguous metadata and incomplete parser definitions."""
    identifiers: set[str] = set()
    swift_names: set[str] = set()
    entry_points: set[str] = set()
    aliases: set[str] = set()
    file_extensions: set[str] = set()
    filenames: set[str] = set()
    native_destinations: set[str] = set()
    query_destinations: set[str] = set()

    for language in languages:
        identifier = required_string(language, "id")
        swift_name = required_string(language, "swiftName")
        entry_point = required_string(language, "entryPoint")
        repository = required_string(language, "repository")
        required_string(language, "displayName")

        require_unique(identifier, identifiers, "language identifier")
        require_unique(swift_name, swift_names, "Swift property")
        require_unique(entry_point, entry_points, "parser entry point")
        if repository not in repositories:
            raise ValueError(
                f"Language '{identifier}' references unknown repository '{repository}'."
            )

        normalized_names = [identifier, *language.get("aliases", [])]
        for name in normalized_names:
            require_unique(name.lower(), aliases, "language identifier or alias")
        for file_extension in language.get("fileExtensions", []):
            require_unique(
                file_extension.lower().lstrip("."),
                file_extensions,
                "file extension",
            )
        for filename in language.get("filenames", []):
            require_unique(
                filename.lower().strip(),
                filenames,
                "filename",
            )

        native_copies = language.get("nativeCopies")
        query_copies = language.get("queryCopies")
        if not isinstance(native_copies, list) or not native_copies:
            raise ValueError(f"Language '{identifier}' has no native sources.")
        if not isinstance(query_copies, list) or not query_copies:
            raise ValueError(f"Language '{identifier}' has no queries.")

        has_highlights = False
        for copy in native_copies:
            validate_copy(copy, repositories, repository)
            require_unique(
                required_string(copy, "destination"),
                native_destinations,
                "native destination",
            )
        for copy in query_copies:
            validate_copy(copy, repositories, repository)
            kind = required_string(copy, "kind")
            if kind not in QUERY_KINDS:
                raise ValueError(
                    f"Language '{identifier}' uses unsupported query kind '{kind}'."
                )
            has_highlights = has_highlights or kind == "highlights"
            destination = f"{identifier}/{required_string(copy, 'destination')}"
            require_unique(destination, query_destinations, "query destination")
        if not has_highlights:
            raise ValueError(f"Language '{identifier}' has no highlights query.")


def required_string(value: dict[str, Any], key: str) -> str:
    """Returns a required nonempty string from a manifest object."""
    result = value.get(key)
    if not isinstance(result, str) or not result:
        raise ValueError(f"Manifest field '{key}' must be a nonempty string.")
    return result


def require_unique(value: str, seen: set[str], description: str) -> None:
    """Adds a value after rejecting a duplicate in the same namespace."""
    if value in seen:
        raise ValueError(f"Duplicate {description} '{value}'.")
    seen.add(value)


def validate_copy(
    copy: dict[str, Any],
    repositories: dict[str, Any],
    default_repository: str,
) -> None:
    """Validates one source-to-destination copy instruction."""
    required_string(copy, "source")
    required_string(copy, "destination")
    repository = copy.get("repository", default_repository)
    if repository not in repositories:
        raise ValueError(f"Copy references unknown repository '{repository}'.")


def checkout_repositories(
    repositories: dict[str, Any],
    checkout_root: Path,
) -> dict[str, Path]:
    """Fetches every exact upstream revision into a temporary directory."""
    checkouts: dict[str, Path] = {}
    for identifier, repository in repositories.items():
        checkout = checkout_root / identifier
        subprocess.run(
            ["git", "init", "--quiet", str(checkout)],
            check=True,
        )
        subprocess.run(
            [
                "git",
                "-C",
                str(checkout),
                "remote",
                "add",
                "origin",
                repository["url"],
            ],
            check=True,
        )
        try:
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(checkout),
                    "fetch",
                    "--quiet",
                    "--depth",
                    "1",
                    "origin",
                    repository["revision"],
                ],
                check=True,
                timeout=GIT_FETCH_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired as error:
            raise TimeoutError(
                f"Fetching repository '{identifier}' exceeded "
                f"{GIT_FETCH_TIMEOUT_SECONDS} seconds."
            ) from error
        subprocess.run(
            [
                "git",
                "-C",
                str(checkout),
                "checkout",
                "--quiet",
                "--detach",
                "FETCH_HEAD",
            ],
            check=True,
        )
        actual_revision = subprocess.run(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        if actual_revision != repository["revision"]:
            raise ValueError(
                f"Repository '{identifier}' resolved to an unexpected revision."
            )
        checkouts[identifier] = checkout
    return checkouts


def copy_path(source: Path, destination: Path) -> None:
    """Copies one declared file or directory without transforming its bytes."""
    if not source.exists():
        raise FileNotFoundError(f"Declared upstream path is missing at {source}.")
    if source.is_dir():
        shutil.copytree(source, destination, dirs_exist_ok=True)
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def populate_staging_output(
    manifest: dict[str, Any],
    checkouts: dict[str, Path],
    output_root: Path,
) -> None:
    """Copies native sources, queries, and licenses into a staged tree."""
    repositories = manifest["repositories"]
    parser_root = output_root / PARSER_SOURCES_PATH
    query_root = output_root / QUERY_RESOURCES_PATH
    license_root = output_root / RETAINED_LICENSES_PATH

    for language in manifest["languages"]:
        default_repository = language["repository"]
        for copy in language["nativeCopies"]:
            repository = copy.get("repository", default_repository)
            copy_path(
                checkouts[repository] / copy["source"],
                parser_root / copy["destination"],
            )
        for copy in language["queryCopies"]:
            repository = copy.get("repository", default_repository)
            copy_path(
                checkouts[repository] / copy["source"],
                query_root / language["id"] / copy["destination"],
            )

    for identifier, repository in repositories.items():
        copy_path(
            checkouts[identifier] / repository["licenseFile"],
            license_root / f"{identifier}.txt",
        )


def render_header(languages: list[dict[str, Any]]) -> str:
    """Renders the documented Clang module interface for every parser."""
    lines = [
        "#ifndef C_RORK_HIGHLIGHTER_PARSERS_H",
        "#define C_RORK_HIGHLIGHTER_PARSERS_H",
        "",
        "/// Represents an immutable Tree-sitter language definition.",
        "typedef struct TSLanguage TSLanguage;",
        "",
        "#ifdef __cplusplus",
        'extern "C" {',
        "#endif",
        "",
    ]
    for language in languages:
        display_name = language["displayName"]
        lines.extend(
            [
                f"/// Returns the process-lifetime Tree-sitter language for {display_name}.",
                "/// The returned pointer remains valid until the process exits.",
                f"const TSLanguage *{language['entryPoint']}(void);",
                "",
            ]
        )
    lines.extend(
        [
            "#ifdef __cplusplus",
            "}",
            "#endif",
            "",
            "#endif",
            "",
        ]
    )
    return "\n".join(lines)


def swift_string(value: str) -> str:
    """Returns a quoted Swift string literal for manifest text."""
    return json.dumps(value, ensure_ascii=False)


def swift_array(values: list[str]) -> str:
    """Returns a compact Swift array literal for short metadata values."""
    return "[" + ", ".join(swift_string(value) for value in values) + "]"


def query_filenames(language: dict[str, Any], kind: str) -> list[str]:
    """Returns query resource names in their declared concatenation order."""
    return [
        copy["destination"]
        for copy in language["queryCopies"]
        if copy["kind"] == kind
    ]


def render_swift(languages: list[dict[str, Any]]) -> str:
    """Renders documented Swift identifiers and standard catalog wiring."""
    lines = [
        "// This file is generated by Scripts/vendor_languages.py.",
        "",
        "import CRorkHighlighterParsers",
        "import Foundation",
        "",
        "/// Adds identifiers for languages distributed with the common parser pack.",
        "extension LanguageID {",
    ]
    for language in languages:
        lines.extend(
            [
                f"    /// Identifies the bundled {language['displayName']} language.",
                (
                    f"    public static let {language['swiftName']}: Self = "
                    f"{swift_string(language['id'])}"
                ),
                "",
            ]
        )
    lines.extend(
        [
            "}",
            "",
            "/// Builds catalogs from the parsers and queries bundled with the package.",
            "extension LanguageCatalog {",
            "    /// Creates the catalog bundled with the package.",
            "    ///",
            "    /// Parser pointers and compiled queries are initialized once per process",
            "    /// and then reused by every standard catalog value.",
            "    ///",
            "    /// - Returns: A catalog containing every bundled language definition.",
            "    /// - Throws: ``HighlighterError`` when a parser or resource is unavailable.",
            "    public static func standard() throws -> Self {",
            "        try standardCatalogResult.get()",
            "    }",
            "",
            "    /// Caches parser validation and query compilation for the process.",
            (
                "    private static let standardCatalogResult: "
                "Result<LanguageCatalog, HighlighterError> = {"
            ),
            "        do {",
            "            return .success(try makeStandardCatalog())",
            "        } catch let error as HighlighterError {",
            "            return .failure(error)",
            "        } catch {",
            "            return .failure(",
            "                .bundledCatalogInitializationFailed(",
            "                    message: String(describing: error)",
            "                )",
            "            )",
            "        }",
            "    }()",
            "",
            "    /// Creates every bundled definition before the result is cached.",
            "    ///",
            "    /// - Returns: A validated language catalog.",
            "    /// - Throws: ``HighlighterError`` when bundled metadata is invalid.",
            "    private static func makeStandardCatalog() throws -> Self {",
            "        let definitions: [BundledLanguageDefinition] = [",
        ]
    )
    for language in languages:
        lines.extend(
            [
                "            BundledLanguageDefinition(",
                f"                id: .{language['swiftName']},",
                f"                displayName: {swift_string(language['displayName'])},",
                f"                aliases: {swift_array(language['aliases'])},",
                (
                    "                fileExtensions: "
                    f"{swift_array(language['fileExtensions'])},"
                ),
                (
                    "                filenames: "
                    f"{swift_array(language.get('filenames', []))},"
                ),
                (
                    "                treeSitterLanguage: "
                    f"{language['entryPoint']}(),"
                ),
                f"                resourceDirectory: {swift_string(language['id'])},",
                (
                    "                highlightsQueries: "
                    f"{swift_array(query_filenames(language, 'highlights'))},"
                ),
                (
                    "                injectionsQueries: "
                    f"{swift_array(query_filenames(language, 'injections'))},"
                ),
                (
                    "                localsQueries: "
                    f"{swift_array(query_filenames(language, 'locals'))}"
                ),
                "            ),",
            ]
        )
    lines.extend(
        [
            "        ]",
            "        return try Self(languages: definitions.map(makeLanguage))",
            "    }",
            "",
            "    /// Creates one public language definition from bundled metadata.",
            "    ///",
            "    /// - Parameter definition: The generated parser and resource metadata.",
            "    /// - Returns: A validated public language definition.",
            "    /// - Throws: ``HighlighterError`` when a parser or query is invalid.",
            "    private static func makeLanguage(",
            "        _ definition: BundledLanguageDefinition",
            "    ) throws -> HighlightLanguage {",
            "        try HighlightLanguage(",
            "            id: definition.id,",
            "            displayName: definition.displayName,",
            "            aliases: definition.aliases,",
            "            fileExtensions: definition.fileExtensions,",
            "            filenames: definition.filenames,",
            "            treeSitterLanguage: definition.treeSitterLanguage,",
            "            highlightsQuery: try query(",
            "                files: definition.highlightsQueries,",
            "                directory: definition.resourceDirectory",
            "            ),",
            "            injectionsQuery: try optionalQuery(",
            "                files: definition.injectionsQueries,",
            "                directory: definition.resourceDirectory",
            "            ),",
            "            localsQuery: try optionalQuery(",
            "                files: definition.localsQueries,",
            "                directory: definition.resourceDirectory",
            "            )",
            "        )",
            "    }",
            "",
            "    /// Concatenates query fragments in their upstream declaration order.",
            "    ///",
            "    /// - Parameters:",
            "    ///   - files: The query filenames to load.",
            "    ///   - directory: The language directory inside package resources.",
            "    /// - Returns: One query source containing every requested fragment.",
            "    /// - Throws: ``HighlighterError`` when a resource cannot be loaded.",
            "    private static func query(",
            "        files: [String],",
            "        directory: String",
            "    ) throws -> String {",
            "        try files.map { filename in",
            "            try resource(filename: filename, directory: directory)",
            "        }.joined(separator: \"\\n\")",
            "    }",
            "",
            "    /// Loads an optional query only when the language declares fragments.",
            "    ///",
            "    /// - Parameters:",
            "    ///   - files: The query filenames to load.",
            "    ///   - directory: The language directory inside package resources.",
            "    /// - Returns: A combined query, or `nil` when no files were declared.",
            "    /// - Throws: ``HighlighterError`` when a resource cannot be loaded.",
            "    private static func optionalQuery(",
            "        files: [String],",
            "        directory: String",
            "    ) throws -> String? {",
            "        guard !files.isEmpty else {",
            "            return nil",
            "        }",
            "        return try query(files: files, directory: directory)",
            "    }",
            "",
            "    /// Loads one UTF-8 query resource from the package bundle.",
            "    ///",
            "    /// - Parameters:",
            "    ///   - filename: The complete query filename.",
            "    ///   - directory: The language directory inside package resources.",
            "    /// - Returns: The decoded UTF-8 query source.",
            "    /// - Throws: ``HighlighterError`` when the resource cannot be loaded.",
            "    private static func resource(",
            "        filename: String,",
            "        directory: String",
            "    ) throws -> String {",
            "        let subdirectory = \"Languages/\\(directory)\"",
            "        let resourceName = (filename as NSString).deletingPathExtension",
            "        let fileExtension = (filename as NSString).pathExtension",
            "        guard",
            "            let url = Bundle.module.url(",
            "                forResource: resourceName,",
            "                withExtension: fileExtension,",
            "                subdirectory: subdirectory",
            "            )",
            "        else {",
            "            throw HighlighterError.missingResource(",
            "                \"\\(subdirectory)/\\(filename)\"",
            "            )",
            "        }",
            "        do {",
            "            return String(decoding: try Data(contentsOf: url), as: UTF8.self)",
            "        } catch {",
            "            throw HighlighterError.unreadableResource(",
            "                resource: \"\\(subdirectory)/\\(filename)\",",
            "                message: String(describing: error)",
            "            )",
            "        }",
            "    }",
            "}",
            "",
            "/// Stores generated metadata for one bundled language.",
            "private struct BundledLanguageDefinition {",
            "    /// Holds the canonical identifier exposed by the public catalog.",
            "    let id: LanguageID",
            "",
            "    /// Holds the human-readable language name.",
            "    let displayName: String",
            "",
            "    /// Holds alternate identifiers accepted by catalog lookup.",
            "    let aliases: Set<LanguageID>",
            "",
            "    /// Holds normalized file extensions associated with the language.",
            "    let fileExtensions: Set<String>",
            "",
            "    /// Holds normalized filenames associated with the language.",
            "    let filenames: Set<String>",
            "",
            "    /// Holds the process-lifetime pointer exported by the generated parser.",
            "    let treeSitterLanguage: OpaquePointer?",
            "",
            "    /// Holds the resource subdirectory containing matching queries.",
            "    let resourceDirectory: String",
            "",
            "    /// Holds highlight query fragments in concatenation order.",
            "    let highlightsQueries: [String]",
            "",
            "    /// Holds injection query fragments in concatenation order.",
            "    let injectionsQueries: [String]",
            "",
            "    /// Holds locals query fragments in concatenation order.",
            "    let localsQueries: [String]",
            "",
            "    /// Creates generated metadata for one bundled language.",
            "    ///",
            "    /// - Parameters:",
            "    ///   - id: The canonical public language identifier.",
            "    ///   - displayName: The human-readable language name.",
            "    ///   - aliases: Alternate identifiers accepted by the catalog.",
            "    ///   - fileExtensions: File extensions associated with the language.",
            "    ///   - filenames: Complete filenames associated with the language.",
            "    ///   - treeSitterLanguage: The generated parser pointer.",
            "    ///   - resourceDirectory: The directory containing matching queries.",
            "    ///   - highlightsQueries: Highlight query fragments in load order.",
            "    ///   - injectionsQueries: Injection query fragments in load order.",
            "    ///   - localsQueries: Locals query fragments in load order.",
            "    init(",
            "        id: LanguageID,",
            "        displayName: String,",
            "        aliases: Set<LanguageID>,",
            "        fileExtensions: Set<String>,",
            "        filenames: Set<String>,",
            "        treeSitterLanguage: OpaquePointer?,",
            "        resourceDirectory: String,",
            "        highlightsQueries: [String],",
            "        injectionsQueries: [String],",
            "        localsQueries: [String]",
            "    ) {",
            "        self.id = id",
            "        self.displayName = displayName",
            "        self.aliases = aliases",
            "        self.fileExtensions = fileExtensions",
            "        self.filenames = filenames",
            "        self.treeSitterLanguage = treeSitterLanguage",
            "        self.resourceDirectory = resourceDirectory",
            "        self.highlightsQueries = highlightsQueries",
            "        self.injectionsQueries = injectionsQueries",
            "        self.localsQueries = localsQueries",
            "    }",
            "}",
            "",
        ]
    )
    return "\n".join(lines)


def write_generated_interfaces(
    manifest: dict[str, Any],
    output_root: Path,
) -> None:
    """Writes the C header and Swift catalog generated from the manifest."""
    header_path = output_root / GENERATED_HEADER_PATH
    swift_path = output_root / GENERATED_SWIFT_PATH
    header_path.parent.mkdir(parents=True, exist_ok=True)
    swift_path.parent.mkdir(parents=True, exist_ok=True)
    header_path.write_text(
        render_header(manifest["languages"]),
        encoding="utf-8",
    )
    swift_path.write_text(
        render_swift(manifest["languages"]),
        encoding="utf-8",
    )
    subprocess.run(
        [
            "swift",
            "format",
            "format",
            "--configuration",
            str(REPOSITORY_ROOT / ".swift-format"),
            "--in-place",
            str(swift_path),
        ],
        cwd=REPOSITORY_ROOT,
        check=True,
    )


def install_staged_output(output_root: Path) -> None:
    """Replaces each managed destination with its complete staged value."""
    for relative_path in MANAGED_PATHS:
        source = output_root / relative_path
        if not source.exists():
            raise FileNotFoundError(
                f"Staged managed output is missing at {source}."
            )

    for relative_path in MANAGED_PATHS:
        source = output_root / relative_path
        destination = REPOSITORY_ROOT / relative_path
        if destination.is_dir():
            shutil.rmtree(destination)
        elif destination.exists():
            destination.unlink()
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, destination)
        else:
            shutil.copyfile(source, destination)


def managed_files(root: Path) -> list[Path]:
    """Returns every regular file contained by the managed output paths."""
    files: list[Path] = []
    for relative_path in MANAGED_PATHS:
        path = root / relative_path
        if path.is_file():
            if path.name not in IGNORED_MANAGED_FILENAMES:
                files.append(path)
        elif path.is_dir():
            files.extend(
                candidate
                for candidate in path.rglob("*")
                if candidate.is_file()
                and candidate.name not in IGNORED_MANAGED_FILENAMES
            )
    return sorted(files)


def sha256(path: Path) -> str:
    """Returns the lowercase SHA-256 digest for one file."""
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def repository_revisions(manifest: dict[str, Any]) -> dict[str, str]:
    """Returns the exact revision associated with every repository key."""
    return {
        identifier: repository["revision"]
        for identifier, repository in manifest["repositories"].items()
    }


def write_lock(manifest: dict[str, Any]) -> None:
    """Records hashes for every generated and vendored output file."""
    files = {
        str(path.relative_to(REPOSITORY_ROOT)): sha256(path)
        for path in managed_files(REPOSITORY_ROOT)
    }
    lock = {
        "schemaVersion": 1,
        "repositories": repository_revisions(manifest),
        "files": files,
    }
    LOCK_PATH.write_text(
        json.dumps(lock, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def update_pack(manifest: dict[str, Any]) -> None:
    """Downloads pinned inputs and installs a reproducible language pack."""
    with tempfile.TemporaryDirectory(
        prefix="rork-highlighter-language-update-"
    ) as temporary_directory:
        temporary_root = Path(temporary_directory)
        checkouts = checkout_repositories(
            manifest["repositories"],
            temporary_root / "checkouts",
        )
        output_root = temporary_root / "output"
        populate_staging_output(manifest, checkouts, output_root)
        write_generated_interfaces(manifest, output_root)
        install_staged_output(output_root)
    write_lock(manifest)
    print(f"Updated {len(manifest['languages'])} bundled languages.")


def verify_generated_interfaces(manifest: dict[str, Any]) -> list[str]:
    """Returns differences between generated interfaces and checked-in files."""
    failures: list[str] = []
    with tempfile.TemporaryDirectory(
        prefix="rork-highlighter-language-check-"
    ) as temporary_directory:
        output_root = Path(temporary_directory)
        write_generated_interfaces(manifest, output_root)
        for relative_path in (
            GENERATED_HEADER_PATH,
            GENERATED_SWIFT_PATH,
        ):
            expected = output_root / relative_path
            actual = REPOSITORY_ROOT / relative_path
            if not actual.exists() or expected.read_bytes() != actual.read_bytes():
                failures.append(f"{relative_path} is not generated from LanguagePack.json.")
    return failures


def verify_parser_entry_points(manifest: dict[str, Any]) -> list[str]:
    """Returns parser definitions whose generated factory cannot be found."""
    failures: list[str] = []
    parser_root = REPOSITORY_ROOT / PARSER_SOURCES_PATH
    for language in manifest["languages"]:
        needles = (
            f"{language['entryPoint']}(void)",
            f"{language['entryPoint']}()",
        )
        parser_files = [
            parser_root / copy["destination"]
            for copy in language["nativeCopies"]
            if copy["destination"].endswith("parser.c")
        ]
        if not any(
            path.is_file()
            and any(
                needle in path.read_text(encoding="utf-8", errors="ignore")
                for needle in needles
            )
            for path in parser_files
        ):
            failures.append(
                f"The parser entry point '{language['entryPoint']}' is missing."
            )
    return failures


def verify_third_party_notices(manifest: dict[str, Any]) -> list[str]:
    """Returns repositories missing their revision or retained license notice."""
    if not NOTICES_PATH.exists():
        return ["THIRD_PARTY_NOTICES.md is missing."]

    notices = NOTICES_PATH.read_text(encoding="utf-8")
    failures: list[str] = []
    for identifier, repository in manifest["repositories"].items():
        retained_license = f"ThirdPartyLicenses/{identifier}.txt"
        if repository["revision"] not in notices:
            failures.append(
                f"THIRD_PARTY_NOTICES.md omits the '{identifier}' revision."
            )
        if retained_license not in notices:
            failures.append(
                f"THIRD_PARTY_NOTICES.md omits '{retained_license}'."
            )
    return failures


def verify_lock(manifest: dict[str, Any]) -> list[str]:
    """Returns missing, unexpected, or modified language pack outputs."""
    if not LOCK_PATH.exists():
        return ["LanguagePack.lock.json is missing."]
    lock = load_json(LOCK_PATH)
    failures: list[str] = []
    if lock.get("schemaVersion") != 1:
        failures.append("LanguagePack.lock.json uses an unsupported schema version.")
    if lock.get("repositories") != repository_revisions(manifest):
        failures.append("LanguagePack.lock.json has stale repository revisions.")

    expected_files = lock.get("files")
    if not isinstance(expected_files, dict):
        return [*failures, "LanguagePack.lock.json has no file hashes."]

    actual_paths = {
        str(path.relative_to(REPOSITORY_ROOT))
        for path in managed_files(REPOSITORY_ROOT)
    }
    expected_paths = set(expected_files)
    for path in sorted(expected_paths.difference(actual_paths)):
        failures.append(f"Managed file '{path}' is missing.")
    for path in sorted(actual_paths.difference(expected_paths)):
        failures.append(f"Managed file '{path}' is not recorded in the lock.")
    for relative_path in sorted(actual_paths.intersection(expected_paths)):
        path = REPOSITORY_ROOT / relative_path
        if sha256(path) != expected_files[relative_path]:
            failures.append(f"Managed file '{relative_path}' has modified bytes.")
    return failures


def check_pack(manifest: dict[str, Any]) -> int:
    """Verifies local outputs without accessing the network."""
    failures = [
        *verify_lock(manifest),
        *verify_generated_interfaces(manifest),
        *verify_parser_entry_points(manifest),
        *verify_third_party_notices(manifest),
    ]
    if failures:
        print("The bundled language pack is out of date:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print(f"Verified {len(manifest['languages'])} bundled languages.")
    return 0


def main() -> int:
    """Updates or verifies the language pack and returns an exit status."""
    arguments = parse_arguments()
    manifest = load_manifest()
    if arguments.update:
        update_pack(manifest)
        return 0
    return check_pack(manifest)


if __name__ == "__main__":
    raise SystemExit(main())
