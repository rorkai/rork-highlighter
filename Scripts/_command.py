"""Provides consistent subprocess execution for repository tooling."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
from typing import Sequence


# External commands fail after this interval instead of blocking CI forever.
DEFAULT_COMMAND_TIMEOUT_SECONDS = 15 * 60


def run_command(
    command: Sequence[str],
    *,
    cwd: Path,
    environment: dict[str, str] | None = None,
    timeout_seconds: float = DEFAULT_COMMAND_TIMEOUT_SECONDS,
) -> subprocess.CompletedProcess[str]:
    """Runs a command with captured text output and a bounded timeout."""
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
        timeout=timeout_seconds,
    )
