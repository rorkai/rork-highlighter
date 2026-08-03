"""Tests generated catalog wiring shared by parser delivery paths."""

import unittest

from Scripts import vendor_languages


class LanguageVendorTests(unittest.TestCase):
    """Verifies generated source that is independent of vendored bytes."""

    def test_generated_catalog_imports_available_parser_module(self) -> None:
        """Selects the binary module first and the source fallback otherwise."""
        source = vendor_languages.render_swift(
            [
                {
                    "id": "swift",
                    "swiftName": "swift",
                    "displayName": "Swift",
                    "aliases": [],
                    "fileExtensions": ["swift"],
                    "entryPoint": "tree_sitter_swift",
                    "queryCopies": [],
                }
            ]
        )

        self.assertIn("#if canImport(CRorkHighlighterParsers)", source)
        self.assertIn("import CRorkHighlighterParsers", source)
        self.assertIn("import CRorkHighlighterSourceParsers", source)


if __name__ == "__main__":
    unittest.main()
