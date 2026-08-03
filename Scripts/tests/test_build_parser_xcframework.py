"""Tests deterministic helpers used by the parser XCFramework builder."""

import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

from Scripts import build_parser_xcframework


class ParserXCFrameworkBuilderTests(unittest.TestCase):
    """Verifies slice selection, archive output, and artifact validation."""

    def test_selects_complete_default_matrix(self) -> None:
        """Includes every declared Apple platform when no filter is given."""
        selected = build_parser_xcframework.select_slices(None, False)

        self.assertEqual(
            [item.name for item in selected],
            [
                "macos",
                "ios",
                "ios-simulator",
                "maccatalyst",
                "tvos",
                "tvos-simulator",
                "watchos",
                "watchos-simulator",
                "visionos",
                "visionos-simulator",
            ],
        )

    def test_selects_one_host_architecture(self) -> None:
        """Restricts the fast smoke artifact to the current macOS architecture."""
        selected = build_parser_xcframework.select_slices(
            None,
            True,
            host_architecture="arm64",
        )

        self.assertEqual(len(selected), 1)
        self.assertEqual(selected[0].name, "macos")
        self.assertEqual(
            [item.name for item in selected[0].architectures],
            ["arm64"],
        )

    def test_selects_requested_slices_in_matrix_order(self) -> None:
        """Filters explicit slices without making output order caller-dependent."""
        selected = build_parser_xcframework.select_slices(
            ["visionos", "ios"],
            False,
        )

        self.assertEqual(
            [item.name for item in selected],
            ["ios", "visionos"],
        )

    def test_rejects_unsupported_host_architecture(self) -> None:
        """Fails instead of silently creating an unusable host artifact."""
        with self.assertRaises(ValueError):
            build_parser_xcframework.select_slices(
                None,
                True,
                host_architecture="powerpc",
            )

    def test_builds_expected_compile_command(self) -> None:
        """Pins optimization, deployment target, SDK, and deterministic output."""
        architecture = build_parser_xcframework.Architecture(
            "arm64",
            "arm64-apple-ios16.0",
        )
        source = Path("/source/parser.c")
        destination = Path("/objects/parser.o")

        with (
            patch.object(
                build_parser_xcframework,
                "xcrun_tool",
                return_value="/toolchain/clang",
            ),
            patch.object(
                build_parser_xcframework,
                "sdk_path",
                return_value="/SDKs/iPhoneOS.sdk",
            ),
        ):
            command = build_parser_xcframework.compile_command(
                source,
                destination,
                architecture,
                "iphoneos",
            )

        self.assertEqual(command[0], "/toolchain/clang")
        self.assertIn("arm64-apple-ios16.0", command)
        self.assertIn("/SDKs/iPhoneOS.sdk", command)
        self.assertIn("-O2", command)
        self.assertEqual(command[-2:], ["-o", str(destination)])

    def test_requests_source_metadata_for_parser_discovery(self) -> None:
        """Selects the source manifest branch while resolving artifact inputs."""
        source = "wrappers/python_scanner.c"
        description = {
            "targets": [
                {
                    "name": build_parser_xcframework.PARSER_TARGET_NAME,
                    "path": "Sources/CRorkHighlighterParsers",
                    "sources": [source],
                }
            ]
        }
        result = Mock(stdout=json.dumps(description))
        source_environment = {
            build_parser_xcframework.PARSER_SOURCE_ENVIRONMENT_VARIABLE: "1"
        }

        with patch.object(
            build_parser_xcframework,
            "run_command",
            return_value=result,
        ) as run_command:
            sources = build_parser_xcframework.parser_sources()

        self.assertEqual(
            sources,
            [
                build_parser_xcframework.REPOSITORY_ROOT
                / "Sources"
                / "CRorkHighlighterParsers"
                / source
            ],
        )
        run_command.assert_called_once_with(
            ["swift", "package", "describe", "--type", "json"],
            environment=source_environment,
        )

    def test_adopted_artifact_matches_locked_parser_sources(self) -> None:
        """Keeps the published parser binary aligned with its source inputs."""
        build_parser_xcframework.validate_adopted_artifact_lock()

    def test_writes_reproducible_archive(self) -> None:
        """Produces identical ZIP bytes after source modification times change."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xcframework = root / "Example.xcframework"
            nested = xcframework / "slice"
            nested.mkdir(parents=True)
            (xcframework / "Info.plist").write_bytes(b"plist")
            (nested / "library.a").write_bytes(b"binary contents")
            first_archive = root / "first.zip"
            second_archive = root / "second.zip"

            build_parser_xcframework.write_deterministic_zip(
                xcframework,
                first_archive,
            )
            (nested / "library.a").touch()
            build_parser_xcframework.write_deterministic_zip(
                xcframework,
                second_archive,
            )

            first_digest = build_parser_xcframework.file_sha256(first_archive)
            second_digest = build_parser_xcframework.file_sha256(second_archive)
            with zipfile.ZipFile(first_archive) as archive:
                names = archive.namelist()

        self.assertEqual(first_digest, second_digest)
        self.assertIn("Example.xcframework/Info.plist", names)
        self.assertIn("Example.xcframework/slice/library.a", names)

    def test_removes_only_the_selected_stale_output(self) -> None:
        """Clears an old artifact without disturbing neighboring output."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stale_output = root / "Example.xcframework"
            stale_output.mkdir()
            (stale_output / "Info.plist").write_bytes(b"old")
            neighbor = root / "keep.txt"
            neighbor.write_bytes(b"keep")

            build_parser_xcframework.remove_existing_output(stale_output)

            self.assertFalse(stale_output.exists())
            self.assertEqual(neighbor.read_bytes(), b"keep")

    def test_validates_xcframework_structure(self) -> None:
        """Accepts a complete library, header, and module map for one slice."""
        specification = build_parser_xcframework.ParserSlice(
            name="macos",
            sdk="macosx",
            supported_platform="macos",
            supported_variant=None,
            architectures=(
                build_parser_xcframework.Architecture(
                    "arm64",
                    "arm64-apple-macos13.0",
                ),
            ),
        )
        with tempfile.TemporaryDirectory() as directory:
            xcframework = Path(directory) / "Example.xcframework"
            slice_directory = xcframework / "macos-arm64"
            headers = slice_directory / "Headers"
            headers.mkdir(parents=True)
            library = slice_directory / "libExample.a"
            library.write_bytes(b"archive")
            (
                headers
                / build_parser_xcframework.PUBLIC_HEADER.name
            ).write_bytes(b"header")
            (headers / "module.modulemap").write_bytes(b"module")
            with (xcframework / "Info.plist").open("wb") as plist_file:
                plistlib.dump(
                    {
                        "AvailableLibraries": [
                            {
                                "LibraryIdentifier": "macos-arm64",
                                "LibraryPath": "libExample.a",
                                "HeadersPath": "Headers",
                                "SupportedArchitectures": ["arm64"],
                                "SupportedPlatform": "macos",
                            }
                        ]
                    },
                    plist_file,
                )

            libraries = (
                build_parser_xcframework.validate_xcframework_structure(
                    xcframework,
                    [specification],
                )
            )

        self.assertEqual(libraries, [library])

    def test_normalizes_generated_xcframework_slice_order(self) -> None:
        """Sorts generated library metadata before deterministic archiving."""
        with tempfile.TemporaryDirectory() as directory:
            xcframework = Path(directory) / "Example.xcframework"
            xcframework.mkdir()
            info_path = xcframework / "Info.plist"
            with info_path.open("wb") as plist_file:
                plistlib.dump(
                    {
                        "AvailableLibraries": [
                            {"LibraryIdentifier": "macos-x86_64"},
                            {"LibraryIdentifier": "ios-arm64"},
                        ]
                    },
                    plist_file,
                )

            build_parser_xcframework.normalize_xcframework_info_plist(
                xcframework
            )

            with info_path.open("rb") as plist_file:
                normalized = plistlib.load(plist_file)

        self.assertEqual(
            [
                item["LibraryIdentifier"]
                for item in normalized["AvailableLibraries"]
            ],
            ["ios-arm64", "macos-x86_64"],
        )

    def test_rejects_malformed_xcframework_slice_metadata(self) -> None:
        """Rejects generated metadata that cannot be canonicalized safely."""
        with tempfile.TemporaryDirectory() as directory:
            xcframework = Path(directory) / "Example.xcframework"
            xcframework.mkdir()
            with (xcframework / "Info.plist").open("wb") as plist_file:
                plistlib.dump(
                    {
                        "AvailableLibraries": [
                            {"LibraryIdentifier": 42}
                        ]
                    },
                    plist_file,
                )

            with self.assertRaisesRegex(ValueError, "malformed"):
                build_parser_xcframework.normalize_xcframework_info_plist(
                    xcframework
                )

    def test_validates_symbols_for_every_library_architecture(self) -> None:
        """Checks each architecture rather than merging universal symbols."""
        library = Path("/artifacts/libParsers.a")
        expected = ["tree_sitter_swift", "tree_sitter_json"]
        symbols = {
            "arm64": set(expected),
            "x86_64": set(expected),
        }
        with (
            patch.object(
                build_parser_xcframework,
                "library_architectures",
                return_value=["arm64", "x86_64"],
            ),
            patch.object(
                build_parser_xcframework,
                "exported_symbols",
                side_effect=lambda _, architecture: symbols[architecture],
            ) as exported_symbols,
        ):
            build_parser_xcframework.validate_exported_symbols(
                [library],
                expected,
            )

        self.assertEqual(exported_symbols.call_count, 2)

    def test_reports_architecture_with_missing_parser_symbol(self) -> None:
        """Identifies the exact architecture that has an incomplete archive."""
        library = Path("/artifacts/libParsers.a")
        expected = ["tree_sitter_swift", "tree_sitter_json"]
        symbols = {
            "arm64": set(expected),
            "x86_64": {"tree_sitter_swift"},
        }
        with (
            patch.object(
                build_parser_xcframework,
                "library_architectures",
                return_value=["arm64", "x86_64"],
            ),
            patch.object(
                build_parser_xcframework,
                "exported_symbols",
                side_effect=lambda _, architecture: symbols[architecture],
            ),
            self.assertRaisesRegex(
                ValueError,
                "x86_64 is missing tree_sitter_json",
            ),
        ):
            build_parser_xcframework.validate_exported_symbols(
                [library],
                expected,
            )

    def test_validates_retained_license_materials(self) -> None:
        """Accepts a complete license tree and rejects a missing retained file."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inputs = root / "inputs"
            licenses = inputs / "ThirdPartyLicenses"
            licenses.mkdir(parents=True)
            package_license = inputs / "LICENSE"
            notices = inputs / "THIRD_PARTY_NOTICES.md"
            grammar_license = licenses / "swift.txt"
            package_license.write_bytes(b"package")
            notices.write_bytes(b"notices")
            grammar_license.write_bytes(b"grammar")

            xcframework = root / "Example.xcframework"
            retained_licenses = xcframework / licenses.name
            retained_licenses.mkdir(parents=True)
            (xcframework / package_license.name).write_bytes(b"package")
            (xcframework / notices.name).write_bytes(b"notices")
            retained_grammar_license = (
                retained_licenses / grammar_license.name
            )
            retained_grammar_license.write_bytes(b"grammar")

            with (
                patch.object(
                    build_parser_xcframework,
                    "PACKAGE_LICENSE",
                    package_license,
                ),
                patch.object(
                    build_parser_xcframework,
                    "THIRD_PARTY_NOTICES",
                    notices,
                ),
                patch.object(
                    build_parser_xcframework,
                    "THIRD_PARTY_LICENSES",
                    licenses,
                ),
            ):
                build_parser_xcframework.validate_license_materials(
                    xcframework
                )
                retained_grammar_license.unlink()
                with self.assertRaises(FileNotFoundError):
                    build_parser_xcframework.validate_license_materials(
                        xcframework
                    )

    def test_generates_smoke_program_for_every_entry_point(self) -> None:
        """Links each constructor so missing archive members cannot go unnoticed."""
        source = build_parser_xcframework.smoke_test_source(
            ["tree_sitter_swift", "tree_sitter_json"]
        )

        self.assertIn("tree_sitter_swift()", source)
        self.assertIn("tree_sitter_json()", source)
        self.assertIn("print(languages.count)", source)

    def test_accepts_swiftpm_progress_before_smoke_program_output(self) -> None:
        """Reads the final program line after any captured SwiftPM progress."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xcframework = root / "Example.xcframework"
            xcframework.mkdir()
            result = Mock(stdout="Building for production...\n2\n")

            with patch.object(
                build_parser_xcframework,
                "run_command",
                return_value=result,
            ):
                build_parser_xcframework.run_swiftpm_smoke_test(
                    xcframework,
                    ["tree_sitter_swift", "tree_sitter_json"],
                    root / "scratch",
                )

    def test_loads_unique_catalog_entry_points(self) -> None:
        """Keeps binary symbol validation aligned with the generated catalog."""
        manifest = json.loads(
            build_parser_xcframework.LANGUAGE_PACK_MANIFEST.read_text(
                encoding="utf-8"
            )
        )
        expected_count = len(manifest["languages"])
        entry_points = build_parser_xcframework.parser_entry_points()

        self.assertEqual(len(entry_points), expected_count)
        self.assertEqual(len(set(entry_points)), expected_count)
        self.assertIn("tree_sitter_swift", entry_points)

    def test_metadata_json_uses_camel_case_keys(self) -> None:
        """Keeps generated sidecar naming consistent with repository manifests."""
        slice_payload = build_parser_xcframework.slice_metadata_payload(
            build_parser_xcframework.SliceMetadata(
                name="macos",
                sdk="macosx",
                platform="macos",
                variant=None,
                architectures=["arm64"],
                library_bytes=42,
            )
        )
        payload = {
            "schemaVersion": 1,
            "workingTreeDirty": False,
            "swiftPMChecksum": "abc",
            "slices": [slice_payload],
        }
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "artifact.json"
            build_parser_xcframework.write_artifact_metadata(payload, output)
            decoded = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(decoded, payload)
        self.assertEqual(decoded["slices"][0]["libraryBytes"], 42)
        self.assertNotIn("library_bytes", decoded["slices"][0])


if __name__ == "__main__":
    unittest.main()
