"""Tests shared subprocess execution for repository tooling."""

from pathlib import Path
import unittest
from unittest.mock import Mock, patch

from Scripts import _command


class CommandTests(unittest.TestCase):
    """Verifies environment merging and bounded command execution."""

    def test_runs_with_merged_environment_and_timeout(self) -> None:
        """Preserves the host environment and applies the requested timeout."""
        result = Mock()
        with (
            patch.dict(_command.os.environ, {"BASE": "present"}, clear=True),
            patch.object(
                _command.subprocess,
                "run",
                return_value=result,
            ) as subprocess_run,
        ):
            returned_result = _command.run_command(
                ["swift", "--version"],
                cwd=Path("/workspace"),
                environment={"EXTRA": "enabled"},
                timeout_seconds=42,
            )

        self.assertIs(returned_result, result)
        subprocess_run.assert_called_once_with(
            ["swift", "--version"],
            cwd=Path("/workspace"),
            check=True,
            capture_output=True,
            text=True,
            env={"BASE": "present", "EXTRA": "enabled"},
            timeout=42,
        )


if __name__ == "__main__":
    unittest.main()
