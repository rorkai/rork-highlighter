"""Tests deterministic generation of cross-runtime benchmark fixtures."""

import json
from pathlib import Path
import tempfile
import unittest

from Scripts import generate_comparison_fixtures


class ComparisonFixtureGenerationTests(unittest.TestCase):
    """Verifies fixture identity and manifest integrity."""

    def test_generates_expected_fixture_sizes(self) -> None:
        """Generates every configured size at or above its lower bound."""
        with tempfile.TemporaryDirectory(
            prefix="rork-highlighter-comparison-fixtures-"
        ) as temporary_directory:
            output_directory = Path(temporary_directory)
            manifest = generate_comparison_fixtures.generate_fixtures(
                output_directory
            )

            self.assertEqual(manifest["schemaVersion"], 1)
            self.assertEqual(manifest["language"], "swift")
            self.assertEqual(len(manifest["fixtures"]), 3)
            for fixture in manifest["fixtures"]:
                self.assertGreaterEqual(
                    fixture["utf16Count"],
                    fixture["minimumUTF16Length"],
                )
                self.assertEqual(
                    fixture["byteCount"],
                    fixture["utf16Count"],
                )

    def test_repeated_generation_is_byte_identical(self) -> None:
        """Produces the same sources and manifest on repeated runs."""
        with tempfile.TemporaryDirectory(
            prefix="rork-highlighter-comparison-fixtures-"
        ) as temporary_directory:
            output_directory = Path(temporary_directory)
            generate_comparison_fixtures.generate_fixtures(output_directory)
            first_contents = {
                path.name: path.read_bytes()
                for path in output_directory.iterdir()
            }

            generate_comparison_fixtures.generate_fixtures(output_directory)
            second_contents = {
                path.name: path.read_bytes()
                for path in output_directory.iterdir()
            }

            self.assertEqual(first_contents, second_contents)

    def test_manifest_matches_generated_files(self) -> None:
        """Records byte counts and names for every generated source file."""
        with tempfile.TemporaryDirectory(
            prefix="rork-highlighter-comparison-fixtures-"
        ) as temporary_directory:
            output_directory = Path(temporary_directory)
            generate_comparison_fixtures.generate_fixtures(output_directory)
            manifest = json.loads(
                (output_directory / "manifest.json").read_text(
                    encoding="utf-8"
                )
            )

            for fixture in manifest["fixtures"]:
                source_path = output_directory / fixture["fileName"]
                self.assertTrue(source_path.is_file())
                self.assertEqual(
                    len(source_path.read_bytes()),
                    fixture["byteCount"],
                )


if __name__ == "__main__":
    unittest.main()
