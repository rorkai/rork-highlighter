"""Tests deterministic helpers used by distribution measurements."""

from pathlib import Path
import tempfile
import unittest

from Scripts import measure_distribution


class DistributionMeasurementTests(unittest.TestCase):
    """Verifies file and artifact size aggregation."""

    def test_rejects_missing_source_directory(self) -> None:
        """Fails when a configured source directory does not exist."""
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "missing"

            with self.assertRaises(FileNotFoundError):
                measure_distribution.measure_files(missing)

    def test_measures_selected_source_files(self) -> None:
        """Counts only requested suffixes and handles a final partial line."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "parser.c").write_bytes(b"one\ntwo\n")
            (root / "scanner.c").write_bytes(b"three")
            (root / "ignored.txt").write_bytes(b"ignored\n")

            measurements = measure_distribution.measure_files(
                root,
                frozenset({".c"}),
            )

        self.assertEqual(measurements.file_count, 2)
        self.assertEqual(measurements.byte_count, 13)
        self.assertEqual(measurements.line_count, 3)

    def test_sums_only_parser_object_files(self) -> None:
        """Excludes object files emitted for unrelated build targets."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            parser_build = (
                root
                / f"{measure_distribution.SOURCE_PARSER_TARGET_NAME}.build"
            )
            parser_build.mkdir()
            (parser_build / "parser.c.o").write_bytes(b"12345")
            other_build = root / "RorkHighlighter.build"
            other_build.mkdir()
            (other_build / "Highlighter.swift.o").write_bytes(b"1234567")

            byte_count = measure_distribution.parser_object_bytes(root)

        self.assertEqual(byte_count, 5)

    def test_sums_extracted_parser_artifacts(self) -> None:
        """Counts complete XCFramework contents beneath the scratch path."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = (
                root
                / "artifacts"
                / (
                    f"{measure_distribution.BINARY_PARSER_MODULE_NAME}"
                    ".xcframework"
                )
            )
            artifact.mkdir(parents=True)
            (artifact / "library.a").write_bytes(b"12345")
            (artifact / "Info.plist").write_bytes(b"123")

            byte_count = measure_distribution.parser_artifact_bytes(root)

        self.assertEqual(byte_count, 8)

    def test_measures_selected_parser_library(self) -> None:
        """Reports the current platform library copied beside build products."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (
                root
                / f"lib{measure_distribution.BINARY_PARSER_MODULE_NAME}.a"
            ).write_bytes(b"12345")

            byte_count = (
                measure_distribution.selected_parser_library_bytes(root)
            )

        self.assertEqual(byte_count, 5)

    def test_builds_source_parser_environment_on_request(self) -> None:
        """Keeps the source measurement aligned with Package.swift."""
        self.assertEqual(
            measure_distribution.parser_build_environment(True),
            {
                measure_distribution.SOURCE_PARSER_ENVIRONMENT_VARIABLE: "1"
            },
        )
        self.assertIsNone(
            measure_distribution.parser_build_environment(False)
        )

    def test_sums_matching_resource_bundles(self) -> None:
        """Includes package resources while ignoring unrelated bundles."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            matching = root / "rork-highlighter_RorkHighlighter.bundle"
            matching.mkdir()
            (matching / "highlights.scm").write_bytes(b"123456")
            unrelated = root / "Other.bundle"
            unrelated.mkdir()
            (unrelated / "resource.txt").write_bytes(b"123456789")

            byte_count = measure_distribution.resource_bundle_bytes(root)

        self.assertEqual(byte_count, 6)


if __name__ == "__main__":
    unittest.main()
