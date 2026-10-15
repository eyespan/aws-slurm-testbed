"""Markers for scheduler smoke tests (executed on a live cluster)."""
import os
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent / "scheduler" / "test_smoke.sh"


@pytest.mark.sandbox
@pytest.mark.skipif(os.environ.get("HPC_LIVE") != "1", reason="Requires live cluster (HPC_LIVE=1)")
def test_scheduler_smoke():
    result = subprocess.run(["bash", str(SCRIPT)], capture_output=True, text=True, timeout=600)
    print(result.stdout)
    print(result.stderr)
    assert result.returncode == 0, result.stdout + result.stderr
