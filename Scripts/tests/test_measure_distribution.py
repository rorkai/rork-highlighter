"""Tests deterministic helpers used by distribution measurements."""

from pathlib import Path
import tempfile
import unittest

from Scripts import measure_distribution


class DistributionMeasurementTests(unittest.TestCase):
    """Verifies file and artifact size aggregation."""

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
            parser_build = root / "CRorkHighlighterParsers.build"
            parser_build.mkdir()
            (parser_build / "parser.c.o").write_bytes(b"12345")
            other_build = root / "RorkHighlighter.build"
            other_build.mkdir()
            (other_build / "Highlighter.swift.o").write_bytes(b"1234567")

            byte_count = measure_distribution.parser_object_bytes(root)

        self.assertEqual(byte_count, 5)

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
