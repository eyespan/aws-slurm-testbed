#!/usr/bin/env python3
"""
Unit tests for preflight.py
"""

from unittest.mock import MagicMock, patch

from scripts.preflight import (
    MAX_INSTANCE_COUNT,
    check_aws_identity,
    check_instance_budget,
    check_policy,
    check_region,
    count_running_instances,
)


class TestCheckAWSIdentity:
    """Tests for check_aws_identity function."""

    @patch("scripts.preflight.boto3")
    def test_check_aws_identity_success(self, mock_boto3):
        """Test successful identity check for cloud_user."""
        mock_sts = MagicMock()
        mock_boto3.client.return_value = mock_sts
        mock_sts.get_caller_identity.return_value = {
            "Arn": "arn:aws:iam::123456789012:user/cloud_user"
        }

        result = check_aws_identity()

        assert result is True
        mock_sts.get_caller_identity.assert_called_once()

    @patch("scripts.preflight.boto3")
    def test_check_aws_identity_wrong_user(self, mock_boto3):
        """Test identity check fails for non-cloud_user."""
        mock_sts = MagicMock()
        mock_boto3.client.return_value = mock_sts
        mock_sts.get_caller_identity.return_value = {
            "Arn": "arn:aws:iam::123456789012:user/other_user"
        }

        result = check_aws_identity()

        assert result is False

    @patch("scripts.preflight.boto3")
    def test_check_aws_identity_exception(self, mock_boto3):
        """Test identity check handles exceptions."""
        mock_sts = MagicMock()
        mock_boto3.client.return_value = mock_sts
        mock_sts.get_caller_identity.side_effect = Exception("AWS Error")

        result = check_aws_identity()

        assert result is False


class TestCheckRegion:
    """Tests for check_region function."""

    @patch("scripts.preflight.boto3.Session")
    def test_check_region_success(self, mock_session):
        """Test successful region check for allowed region."""
        mock_session_instance = MagicMock()
        mock_session.return_value = mock_session_instance
        mock_session_instance.region_name = "us-east-1"

        result = check_region()

        assert result is True

    @patch("scripts.preflight.boto3.Session")
    def test_check_region_not_allowed(self, mock_session):
        """Test region check fails for non-allowed region."""
        mock_session_instance = MagicMock()
        mock_session.return_value = mock_session_instance
        mock_session_instance.region_name = "eu-west-1"

        result = check_region()

        assert result is False

    @patch("scripts.preflight.boto3.Session")
    def test_check_region_fallback_to_config(self, mock_session):
        """Test region check falls back to aws configure."""
        mock_session_instance = MagicMock()
        mock_session.return_value = mock_session_instance
        mock_session_instance.region_name = None

        with patch("subprocess.run") as mock_subprocess:
            mock_subprocess.return_value.stdout = "us-west-2\n"
            mock_subprocess.return_value.returncode = 0

            result = check_region()

            assert result is True
            mock_subprocess.assert_called()


class TestCountRunningInstances:
    """Tests for count_running_instances function."""

    @patch("scripts.preflight.boto3.client")
    def test_count_running_instances_success(self, mock_client):
        """Test successful instance count."""
        mock_ec2 = MagicMock()
        mock_client.return_value = mock_ec2
        mock_ec2.describe_instances.return_value = {
            "Reservations": [
                {"Instances": [{"InstanceId": "i-1"}, {"InstanceId": "i-2"}]},
                {"Instances": [{"InstanceId": "i-3"}]},
            ]
        }

        count = count_running_instances()

        assert count == 3
        mock_ec2.describe_instances.assert_called_once()

    @patch("scripts.preflight.boto3.client")
    def test_count_running_instances_no_reservations(self, mock_client):
        """Test instance count with no reservations."""
        mock_ec2 = MagicMock()
        mock_client.return_value = mock_ec2
        mock_ec2.describe_instances.return_value = {"Reservations": []}

        count = count_running_instances()

        assert count == 0

    @patch("scripts.preflight.boto3.client")
    def test_count_running_instances_exception(self, mock_client):
        """Test instance count handles exceptions."""
        mock_ec2 = MagicMock()
        mock_client.return_value = mock_ec2
        mock_ec2.describe_instances.side_effect = Exception("AWS Error")

        count = count_running_instances()

        assert count is None


class TestCheckInstanceBudget:
    """Tests for check_instance_budget function."""

    @patch("scripts.preflight.count_running_instances")
    def test_check_instance_budget_success(self, mock_count):
        """Test budget check passes within limit."""
        mock_count.return_value = 5

        result = check_instance_budget()

        assert result is True

    @patch("scripts.preflight.count_running_instances")
    def test_check_instance_budget_exceeded(self, mock_count):
        """Test budget check fails when exceeded."""
        mock_count.return_value = MAX_INSTANCE_COUNT + 1

        result = check_instance_budget()

        assert result is False

    @patch("scripts.preflight.count_running_instances")
    def test_check_instance_budget_at_limit(self, mock_count):
        """Test budget check passes at exactly the limit."""
        mock_count.return_value = MAX_INSTANCE_COUNT

        result = check_instance_budget()

        assert result is True

    @patch("scripts.preflight.count_running_instances")
    def test_check_instance_budget_count_error(self, mock_count):
        """Test budget check handles count errors."""
        mock_count.return_value = None

        result = check_instance_budget()

        assert result is False


class TestCheckPolicy:
    """Tests for check_policy function."""

    @patch("scripts.preflight.Path")
    @patch("subprocess.run")
    def test_check_policy_no_plan_file(self, mock_subprocess, mock_path):
        """Test policy check skips when no plan file exists."""
        mock_path.return_value.exists.return_value = False

        result = check_policy()

        assert result is True
        mock_subprocess.assert_not_called()

    @patch("scripts.preflight.Path")
    @patch("subprocess.run")
    def test_check_policy_success(self, mock_subprocess, mock_path):
        """Test policy check passes."""
        mock_path.return_value.exists.return_value = True
        mock_subprocess.return_value.returncode = 0
        mock_subprocess.return_value.stdout = "Policy check passed"
        mock_subprocess.return_value.stderr = ""

        result = check_policy()

        assert result is True

    @patch("scripts.preflight.Path")
    @patch("subprocess.run")
    def test_check_policy_failure(self, mock_subprocess, mock_path):
        """Test policy check fails."""
        mock_path.return_value.exists.return_value = True
        mock_subprocess.return_value.returncode = 1
        mock_subprocess.return_value.stdout = "Policy violation"
        mock_subprocess.return_value.stderr = ""

        result = check_policy()

        assert result is False

    @patch("scripts.preflight.Path")
    @patch("subprocess.run")
    def test_check_policy_exception(self, mock_subprocess, mock_path):
        """Test policy check handles exceptions."""
        mock_path.return_value.exists.return_value = True
        mock_subprocess.side_effect = Exception("Error")

        result = check_policy()

        assert result is False
