"""Tests the source-level Swift documentation scanner."""

import unittest

from Scripts import check_documentation


class SupportingSwiftDeclarationTests(unittest.TestCase):
    """Verifies supporting declarations are separated from local code."""

    def test_includes_private_set_property(self) -> None:
        """Recognizes a property with restricted setter access."""
        lines = [
            "struct State {",
            "    private(set) var value: Int",
            "}",
        ]

        self.assertTrue(
            check_documentation.is_supporting_swift_declaration(
                lines,
                1,
            )
        )

    def test_excludes_function_local_binding(self) -> None:
        """Ignores a local binding inside a top-level function."""
        lines = [
            "func render() {",
            "    let localValue = 1",
            "}",
        ]

        self.assertFalse(
            check_documentation.is_supporting_swift_declaration(
                lines,
                1,
            )
        )

    def test_excludes_function_local_type_and_member(self) -> None:
        """Ignores a type and its member when both are function-local."""
        lines = [
            "func render() {",
            "    struct LocalState {",
            "        var value: Int",
            "    }",
            "}",
        ]

        self.assertFalse(
            check_documentation.is_supporting_swift_declaration(
                lines,
                1,
            )
        )
        self.assertFalse(
            check_documentation.is_supporting_swift_declaration(
                lines,
                2,
            )
        )

    def test_includes_conditionally_compiled_type_member(self) -> None:
        """Recognizes a type member below conditional indentation."""
        lines = [
            "#if canImport(AppKit)",
            "    struct Preview {",
            "        let title: String",
            "    }",
            "#endif",
        ]

        self.assertTrue(
            check_documentation.is_supporting_swift_declaration(
                lines,
                2,
            )
        )

    def test_excludes_multiline_string_contents(self) -> None:
        """Ignores declaration-like fixture text inside a multiline string."""
        lines = [
            'let source = """',
            "    struct Fixture {",
            "        let value: Int",
            "    }",
            '    """',
        ]

        self.assertEqual(
            check_documentation.swift_multiline_string_content_lines(
                lines
            ),
            {1, 2, 3, 4},
        )


if __name__ == "__main__":
    unittest.main()
