"""Unit tests for hpcops CLI with mocked Slurm commands."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "automation" / "python"))

from hpcops.cli import drain_node, diagnose_job, diagnose_node, requeue_stuck, _parse_elapsed  # noqa: E402


def test_parse_elapsed():
    assert _parse_elapsed("05") == 5
    assert _parse_elapsed("01:02") == 62
    assert _parse_elapsed("1:02:03") == 3723
    assert _parse_elapsed("2-01:00:00") == 2 * 86400 + 3600


def test_drain_dry_run(tmp_path, monkeypatch):
    log = tmp_path / "ops-log.jsonl"
    monkeypatch.setenv("HPC_OPS_LOG", str(log))
    with patch("hpcops.cli.run_cmd") as rc:
        assert drain_node("debug-1", "test", yes=False) == 0
        rc.assert_not_called()
    records = [json.loads(l) for l in log.read_text().splitlines()]
    assert records[0]["action"] == "drain-node"
    assert records[0]["dry_run"] is True


def test_drain_yes(tmp_path, monkeypatch):
    log = tmp_path / "ops-log.jsonl"
    monkeypatch.setenv("HPC_OPS_LOG", str(log))
    with patch("hpcops.cli.run_cmd") as rc:
        rc.return_value = MagicMock(returncode=0, stdout="", stderr="")
        assert drain_node("debug-1", "test", yes=True) == 0
        rc.assert_called_once()
    assert "dry_run\": false" in log.read_text().replace(" ", "") or '"dry_run": false' in log.read_text()


def test_diagnose_job(tmp_path, monkeypatch):
    log = tmp_path / "ops-log.jsonl"
    monkeypatch.setenv("HPC_OPS_LOG", str(log))
    with patch("hpcops.cli.run_cmd") as rc:
        rc.return_value = MagicMock(returncode=0, stdout="JobId=1", stderr="")
        assert diagnose_job("1") == 0
        assert rc.call_count == 2


def test_requeue_stuck_none(tmp_path, monkeypatch):
    log = tmp_path / "ops-log.jsonl"
    monkeypatch.setenv("HPC_OPS_LOG", str(log))
    with patch("hpcops.cli.run_cmd") as rc:
        rc.return_value = MagicMock(returncode=0, stdout="", stderr="")
        assert requeue_stuck(30, yes=False) == 0
