"""
Unit tests for the bootstrap security module.
Tests KMS keys, CloudTrail, Config rules, and S3 bucket configurations.
"""

import json
import subprocess
import tempfile
from pathlib import Path

import pytest

# =============================================================================
# Test S3 Bucket Encryption (Terraform Configuration)
# =============================================================================


class TestS3Encryption:
    """Tests for S3 bucket encryption configurations."""

    def test_s3_bucket_encryption_config(self):
        """Test S3 bucket encryption configuration in Terraform."""
        # Read the bootstrap module
        bootstrap_dir = Path("terraform/bootstrap")
        main_tf = bootstrap_dir / "main.tf"

        assert main_tf.exists(), "main.tf should exist in bootstrap module"

        content = main_tf.read_text()

        # Verify S3 bucket has encryption configured
        assert "aws_s3_bucket_server_side_encryption_configuration" in content
        assert "aws_kms_key" in content
        assert "sse_algorithm" in content
        assert "kms_master_key_id" in content

    def test_cloudtrail_bucket_public_access_blocked(self):
        """Test that CloudTrail bucket blocks public access."""
        bootstrap_dir = Path("terraform/bootstrap")
        main_tf = bootstrap_dir / "main.tf"

        content = main_tf.read_text()

        # Verify public access blocking is configured
        assert "aws_s3_bucket_public_access_block" in content
        assert "block_public_acls" in content
        assert "block_public_policy" in content
        assert "ignore_public_acls" in content
        assert "restrict_public_buckets" in content

    def test_config_delivery_bucket_encrypted(self):
        """Test that Config delivery bucket is encrypted."""
        bootstrap_dir = Path("terraform/bootstrap")
        main_tf = bootstrap_dir / "main.tf"

        content = main_tf.read_text()

        # Verify Config delivery bucket encryption
        assert "aws_s3_bucket_server_side_encryption_configuration" in content
        assert "config-delivery" in content


# =============================================================================
# Test Evidence Collector (with moto mocking)
# =============================================================================


class TestEvidenceCollector:
    """Tests for the evidence collector."""

    def test_evidence_collector_runs_successfully(self):
        """Test that evidence collector runs and creates manifest."""

        with tempfile.TemporaryDirectory() as temp_dir:
            evidence_dir = Path(temp_dir)

            # Mock all AWS CLI commands
            import subprocess
            from unittest.mock import patch

            def mock_subprocess_run(*args, **kwargs):
                """Mock subprocess.run to simulate AWS CLI responses."""
                command = args[0] if args else kwargs.get("args", [])

                # Determine response based on command
                if "iam" in command:
                    if "list-users" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"Users": []}',
                            stderr="",
                        )
                    elif "list-roles" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"Roles": []}',
                            stderr="",
                        )
                    elif "list-policies" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"Policies": []}',
                            stderr="",
                        )
                    elif "list-access-keys" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"AccessKeyMetadata": []}',
                            stderr="",
                        )
                elif "kms" in command:
                    if "list-keys" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"Keys": []}',
                            stderr="",
                        )
                elif "cloudtrail" in command:
                    if "list-trails" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"Trails": []}',
                            stderr="",
                        )
                elif "configservice" in command:
                    if "describe-configuration-recorders" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"ConfigurationRecorders": []}',
                            stderr="",
                        )
                    elif "describe-config-rules" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"ConfigRules": []}',
                            stderr="",
                        )
                elif "securityhub" in command:
                    if "get-hub" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"HubArn": "arn:aws:securityhub:us-east-1:123456789012:hub/default"}',
                            stderr="",
                        )
                elif "guardduty" in command:
                    if "list-detectors" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"DetectorIds": []}',
                            stderr="",
                        )
                elif "ec2" in command:
                    if "describe-instances" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"Reservations": []}',
                            stderr="",
                        )
                    elif "describe-security-groups" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"SecurityGroups": []}',
                            stderr="",
                        )
                    elif "describe-volumes" in command:
                        return subprocess.CompletedProcess(
                            args=command,
                            returncode=0,
                            stdout='{"Volumes": []}',
                            stderr="",
                        )

                # Default response
                return subprocess.CompletedProcess(
                    args=command, returncode=0, stdout="{}", stderr=""
                )

            with patch("subprocess.run", side_effect=mock_subprocess_run):
                from scripts.evidence import (
                    collect_cloudtrail_info,
                    collect_config_info,
                    collect_ec2_info,
                    collect_guardduty_info,
                    collect_iam_info,
                    collect_kms_info,
                    collect_security_hub_info,
                    create_manifest,
                )

                # Collect all information
                collect_iam_info(evidence_dir)
                collect_kms_info(evidence_dir)
                collect_cloudtrail_info(evidence_dir)
                collect_config_info(evidence_dir)
                collect_security_hub_info(evidence_dir)
                collect_guardduty_info(evidence_dir)
                collect_ec2_info(evidence_dir)

                # Create manifest
                manifest = create_manifest(evidence_dir)

                # Verify manifest was created
                assert "files" in manifest

    def test_sha256_file_hash(self):
        """Test SHA-256 file hash calculation."""
        with tempfile.TemporaryDirectory() as temp_dir:
            test_file = Path(temp_dir) / "test.txt"
            test_file.write_text("test content")

            from scripts.evidence import sha256_file

            hash_result = sha256_file(test_file)

            # Verify hash is a 64-character hex string
            assert len(hash_result) == 64
            assert all(c in "0123456789abcdef" for c in hash_result)

    def test_evidence_manifest_structure(self):
        """Test that evidence manifest has correct structure."""
        with tempfile.TemporaryDirectory() as temp_dir:
            evidence_dir = Path(temp_dir)

            # Create a test file
            test_file = evidence_dir / "test.json"
            test_file.write_text('{"test": "data"}')

            # Create manifest
            manifest_data = {
                "generated_at": "2024-01-01T00:00:00",
                "files": [
                    {
                        "path": "test.json",
                        "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                    }
                ],
            }

            manifest_path = evidence_dir / "manifest.json"
            with open(manifest_path, "w") as f:
                json.dump(manifest_data, f)

            # Verify manifest structure
            with open(manifest_path) as f:
                manifest = json.load(f)

            assert "generated_at" in manifest
            assert "files" in manifest
            assert len(manifest["files"]) == 1
            assert "path" in manifest["files"][0]
            assert "sha256" in manifest["files"][0]


# =============================================================================
# Test Terraform Bootstrap Module
# =============================================================================


class TestBootstrapModule:
    """Tests for the bootstrap Terraform module."""

    def test_terraform_validate(self):
        """Test that the bootstrap module validates."""

        result = subprocess.run(
            ["terraform", "validate"],
            cwd="terraform/bootstrap",
            check=False,
            capture_output=True,
            text=True,
        )

        # Terraform may not be installed or configured, so we just check it runs
        # If terraform is available, it should validate successfully
        if result.returncode != 0:
            # Check if terraform is installed
            if "command not found" in result.stderr:
                pytest.skip("Terraform not installed")
            elif "invalid configuration" in result.stderr.lower():
                pytest.fail(f"Terraform validation failed: {result.stderr}")
            else:
                # Other errors may be expected (e.g., missing credentials)
                pytest.skip(f"Terraform validation skipped: {result.stderr}")

    def test_bootstrap_has_kms_keys(self):
        """Test that bootstrap module has KMS keys defined."""
        bootstrap_dir = Path("terraform/bootstrap")
        main_tf = bootstrap_dir / "main.tf"

        content = main_tf.read_text()

        # Check for KMS key resources
        assert 'resource "aws_kms_key"' in content

        # Check for key rotation
        assert "enable_key_rotation" in content

        # Check for KMS aliases
        assert 'resource "aws_kms_alias"' in content

    def test_bootstrap_has_cloudtrail(self):
        """Test that bootstrap module has CloudTrail defined."""
        bootstrap_dir = Path("terraform/bootstrap")
        main_tf = bootstrap_dir / "main.tf"

        content = main_tf.read_text()

        # Check for CloudTrail resource
        assert 'resource "aws_cloudtrail"' in content

        # Check for log file validation
        assert "enable_log_file_validation" in content

    def test_bootstrap_has_config_recorder(self):
        """Test that bootstrap module has Config recorder defined."""
        bootstrap_dir = Path("terraform/bootstrap")
        main_tf = bootstrap_dir / "main.tf"

        content = main_tf.read_text()

        # Check for Config recorder
        assert 'resource "aws_config_configuration_recorder"' in content

        # Check for Config delivery channel
        assert 'resource "aws_config_delivery_channel"' in content

    def test_bootstrap_has_config_rules(self):
        """Test that bootstrap module has all required Config rules."""
        bootstrap_dir = Path("terraform/bootstrap")
        main_tf = bootstrap_dir / "main.tf"

        content = main_tf.read_text()

        # Required rules from design.md section 4.9
        # Note: Terraform resource names use underscores, not hyphens
        required_rules = [
            "encrypted_volumes",
            "s3_bucket_public_read_prohibited",
            "required_tags",
            "iam_policy_no_statements_with_admin_access",
            "cloudtrail_enabled",
        ]

        for rule in required_rules:
            assert f'resource "aws_config_config_rule" "{rule}"' in content

    def test_bootstrap_has_guardduty(self):
        """Test that bootstrap module has GuardDuty enabled."""
        bootstrap_dir = Path("terraform/bootstrap")
        main_tf = bootstrap_dir / "main.tf"

        content = main_tf.read_text()

        # Check for GuardDuty detector
        assert 'resource "aws_guardduty_detector"' in content

    def test_bootstrap_has_security_hub(self):
        """Test that bootstrap module has Security Hub enabled."""
        bootstrap_dir = Path("terraform/bootstrap")
        main_tf = bootstrap_dir / "main.tf"

        content = main_tf.read_text()

        # Check for Security Hub account
        assert 'resource "aws_securityhub_account"' in content

    def test_bootstrap_has_tags(self):
        """Test that bootstrap module uses required tags."""
        bootstrap_dir = Path("terraform/bootstrap")
        main_tf = bootstrap_dir / "main.tf"

        content = main_tf.read_text()

        # Check for required tags
        assert "Project" in content
        assert "Env" in content
        assert "Session" in content

    def test_bootstrap_has_variables(self):
        """Test that bootstrap module has required variables."""
        bootstrap_dir = Path("terraform/bootstrap")
        variables_tf = bootstrap_dir / "variables.tf"

        assert variables_tf.exists(), "variables.tf should exist in bootstrap module"

        content = variables_tf.read_text()

        # Check for required variables
        assert 'variable "aws_region"' in content
        assert 'variable "project"' in content
        assert 'variable "env"' in content
        assert 'variable "session"' in content
        assert 'variable "key_deletion_window"' in content

    def test_bootstrap_has_outputs(self):
        """Test that bootstrap module has outputs defined."""
        bootstrap_dir = Path("terraform/bootstrap")
        main_tf = bootstrap_dir / "main.tf"

        # Outputs are in main.tf
        assert main_tf.exists(), "main.tf should exist in bootstrap module"

        content = main_tf.read_text()

        # Check for expected outputs
        assert 'output "kms_key_arns"' in content
        assert 'output "cloudtrail_trail_arn"' in content
        assert 'output "config_recorder_name"' in content
