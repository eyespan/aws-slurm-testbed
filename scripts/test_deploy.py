#!/usr/bin/env python3
"""
Unit tests for deploy.py
"""

import json
from unittest.mock import MagicMock, patch

from scripts.deploy import (
    EVIDENCE_DIR,
    destroy_tagged_resources,
    ensure_evidence_dir,
    export_evidence,
    generate_session_id,
    terraform_apply,
    terraform_destroy,
)


class TestGenerateSessionID:
    """Tests for generate_session_id function."""

    def test_generate_session_id_returns_string(self):
        """Test session ID is a string."""
        session_id = generate_session_id()

        assert isinstance(session_id, str)
        assert len(session_id) == 8  # First 8 chars of UUID

    def test_generate_session_id_is_unique(self):
        """Test session IDs are unique."""
        session1 = generate_session_id()
        session2 = generate_session_id()

        assert session1 != session2


class TestEnsureEvidenceDir:
    """Tests for ensure_evidence_dir function."""

    def test_ensure_evidence_dir_exists(self, tmp_path):
        """Test evidence directory is created."""
        with patch.object(
            EVIDENCE_DIR, "__fspath__", return_value=str(tmp_path / "evidence")
        ):
            result = ensure_evidence_dir()

            assert result.exists()
            assert result.is_dir()


class TestExportEvidence:
    """Tests for export_evidence function."""

    @patch("scripts.deploy.datetime")
    @patch("scripts.deploy.subprocess.run")
    @patch("scripts.deploy.ensure_evidence_dir")
    def test_export_evidence_success(self, mock_ensure, mock_subprocess, mock_datetime):
        """Test evidence export succeeds."""
        mock_datetime.now.return_value.strftime.return_value = "20240101_120000"
        mock_subprocess.return_value.returncode = 0
        mock_subprocess.return_value.stdout = json.dumps({"Reservations": []})
        mock_ensure.return_value = MagicMock()

        session_id, evidence_dir = export_evidence("test")

        assert session_id is not None
        assert evidence_dir is not None
        mock_subprocess.assert_called()

    @patch("scripts.deploy.subprocess.run")
    def test_export_evidence_aws_error(self, mock_subprocess):
        """Test evidence export handles AWS errors."""
        mock_subprocess.return_value.returncode = 1
        mock_subprocess.return_value.stdout = ""
        mock_subprocess.return_value.stderr = "AWS Error"

        session_id, evidence_dir = export_evidence("test")

        assert session_id is not None
        assert evidence_dir is not None


class TestTerraformApply:
    """Tests for terraform_apply function."""

    @patch("scripts.deploy.subprocess.run")
    def test_terraform_apply_success(self, mock_subprocess):
        """Test terraform apply succeeds."""
        mock_subprocess.return_value.returncode = 0
        mock_subprocess.return_value.stdout = "Apply complete!"
        mock_subprocess.return_value.stderr = ""

        result = terraform_apply("test-session")

        assert result is True
        mock_subprocess.assert_called()

    @patch("scripts.deploy.subprocess.run")
    def test_terraform_apply_failure(self, mock_subprocess):
        """Test terraform apply fails."""
        mock_subprocess.return_value.returncode = 1
        mock_subprocess.return_value.stdout = "Error"
        mock_subprocess.return_value.stderr = "AWS Error"

        result = terraform_apply("test-session")

        assert result is False


class TestTerraformDestroy:
    """Tests for terraform_destroy function."""

    @patch("scripts.deploy.subprocess.run")
    def test_terraform_destroy_success(self, mock_subprocess):
        """Test terraform destroy succeeds."""
        mock_subprocess.return_value.returncode = 0
        mock_subprocess.return_value.stdout = "Destroy complete!"
        mock_subprocess.return_value.stderr = ""

        result = terraform_destroy("test-session")

        assert result is True
        mock_subprocess.assert_called()

    @patch("scripts.deploy.subprocess.run")
    def test_terraform_destroy_failure(self, mock_subprocess):
        """Test terraform destroy fails."""
        mock_subprocess.return_value.returncode = 1
        mock_subprocess.return_value.stdout = "Error"
        mock_subprocess.return_value.stderr = "AWS Error"

        result = terraform_destroy("test-session")

        assert result is False


class TestDestroyTaggedResources:
    """Tests for destroy_tagged_resources function."""

    @patch("scripts.deploy.subprocess.run")
    def test_destroy_tagged_resources_no_instances(self, mock_subprocess):
        """Test resource cleanup when no instances found."""
        mock_subprocess.return_value.returncode = 0
        mock_subprocess.return_value.stdout = ""

        result = destroy_tagged_resources("test-session")

        assert result is True

    @patch("scripts.deploy.subprocess.run")
    def test_destroy_tagged_resources_with_instances(self, mock_subprocess):
        """Test resource cleanup with instances."""

        # Mock describe-instances response
        def mock_run_side_effect(args, **kwargs):
            mock_result = MagicMock()
            if "describe-instances" in args:
                mock_result.stdout = "i-1234567890\n"
            elif "describe-volumes" in args:
                mock_result.stdout = ""
            else:
                mock_result.returncode = 0
            return mock_result

        mock_subprocess.side_effect = mock_run_side_effect

        result = destroy_tagged_resources("test-session")

        assert result is True
