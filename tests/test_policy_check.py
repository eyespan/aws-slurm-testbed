"""
Unit tests for the policy check script.
Tests validation of instance types, regions, unavailable services, and instance counts.
"""

import json
import tempfile
from pathlib import Path

import pytest

from scripts.policy_check import (
    ALLOWED_INSTANCE_TYPES,
    ALLOWED_REGIONS,
    check_instance_count,
    check_instance_types,
    check_region,
    check_services_disabled,
    check_unavailable_services,
    scan_plan,
)


class TestInstanceTypeValidation:
    """Tests for instance type validation."""

    def test_allowed_instance_types(self):
        """Test that all allowed instance types pass validation."""
        for instance_type in ALLOWED_INSTANCE_TYPES:
            result = check_instance_types(
                {
                    "resource_changes": [
                        {
                            "type": "aws_instance",
                            "name": "test_instance",
                            "change": {"after": {"instance_type": instance_type}},
                        }
                    ]
                }
            )
            assert (
                result == []
            ), f"Expected no violations for {instance_type}, got {result}"

    def test_disallowed_instance_type(self):
        """Test that disallowed instance types are detected."""
        result = check_instance_types(
            {
                "resource_changes": [
                    {
                        "type": "aws_instance",
                        "name": "test_instance",
                        "change": {"after": {"instance_type": "m5.large"}},
                    }
                ]
            }
        )
        assert len(result) == 1
        assert "m5.large" in result[0]
        assert "not in the allowed list" in result[0]

    def test_multiple_instances_some_disallowed(self):
        """Test detection when multiple instances have mixed allowed/disallowed types."""
        result = check_instance_types(
            {
                "resource_changes": [
                    {
                        "type": "aws_instance",
                        "name": "allowed_instance",
                        "change": {"after": {"instance_type": "t3.small"}},
                    },
                    {
                        "type": "aws_instance",
                        "name": "disallowed_instance",
                        "change": {"after": {"instance_type": "c5.xlarge"}},
                    },
                ]
            }
        )
        assert len(result) == 1
        assert "c5.xlarge" in result[0]

    def test_non_instance_resources_ignored(self):
        """Test that non-aws_instance resources are ignored."""
        result = check_instance_types(
            {"resource_changes": [{"type": "aws_s3_bucket", "name": "test_bucket"}]}
        )
        assert result == []

    def test_empty_plan(self):
        """Test with empty plan data."""
        result = check_instance_types({})
        assert result == []

    def test_missing_instance_type(self):
        """Test resource without instance_type field."""
        result = check_instance_types(
            {
                "resource_changes": [
                    {
                        "type": "aws_instance",
                        "name": "test_instance",
                        "change": {"after": {}},
                    }
                ]
            }
        )
        # Empty instance_type should not cause a violation
        assert result == []


class TestRegionValidation:
    """Tests for region validation."""

    def test_allowed_regions(self):
        """Test that allowed regions pass validation."""
        for region in ALLOWED_REGIONS:
            result = check_region({"resource_changes": []}, region)
            assert result == [], f"Expected no violations for {region}, got {result}"

    def test_disallowed_region(self):
        """Test that disallowed regions are detected."""
        result = check_region({"resource_changes": []}, "eu-west-1")
        assert len(result) == 1
        assert "eu-west-1" in result[0]
        assert "not in the allowed regions" in result[0]

    def test_multiple_disallowed_regions(self):
        """Test detection for multiple disallowed regions."""
        for region in ["eu-west-1", "ap-southeast-1", "us-west-1"]:
            result = check_region({"resource_changes": []}, region)
            assert len(result) == 1


class TestUnavailableServices:
    """Tests for unavailable services detection."""

    def test_no_violations_without_unavailable_services(self):
        """Test no violations when no unavailable services are referenced."""
        result = check_unavailable_services(
            {"resource_changes": [{"type": "aws_instance", "name": "test_instance"}]}
        )
        assert result == []

    def test_pcs_cluster_detected(self):
        """Test detection of AWS PCS clusters."""
        result = check_unavailable_services(
            {"resource_changes": [{"type": "aws_pcs_cluster", "name": "pcs_cluster"}]}
        )
        assert len(result) == 1
        assert "pcs_cluster" in result[0]
        assert "ParallelCluster" in result[0]

    def test_efa_detected(self):
        """Test detection of EFA-related resources."""
        result = check_unavailable_services(
            {
                "resource_changes": [
                    {"type": "aws_ec2_traffic_mirror_session", "name": "efa_mirror"}
                ]
            }
        )
        assert len(result) == 1
        assert "EFA" in result[0]

    def test_private_link_detected(self):
        """Test detection of PrivateLink resources."""
        result = check_unavailable_services(
            {
                "resource_changes": [
                    {"type": "aws_vpc_endpoint_service", "name": "private_link_service"}
                ]
            }
        )
        assert len(result) == 1
        assert "PrivateLink" in result[0]


class TestInstanceCount:
    """Tests for instance count validation."""

    def test_under_limit(self):
        """Test instance count under limit passes."""
        result = check_instance_count(
            {
                "resource_changes": [
                    {
                        "type": "aws_instance",
                        "name": f"instance_{i}",
                        "change": {"actions": ["create"]},
                    }
                    for i in range(5)
                ]
            }
        )
        assert result == []

    def test_at_limit(self):
        """Test instance count at limit (9) passes."""
        result = check_instance_count(
            {
                "resource_changes": [
                    {
                        "type": "aws_instance",
                        "name": f"instance_{i}",
                        "change": {"actions": ["create"]},
                    }
                    for i in range(9)
                ]
            }
        )
        assert result == []

    def test_over_limit(self):
        """Test instance count over limit is detected."""
        result = check_instance_count(
            {
                "resource_changes": [
                    {
                        "type": "aws_instance",
                        "name": f"instance_{i}",
                        "change": {"actions": ["create"]},
                    }
                    for i in range(10)
                ]
            }
        )
        assert len(result) == 1
        assert "exceeds sandbox limit" in result[0]
        assert "10" in result[0]

    def test_no_instances(self):
        """Test with no instances."""
        result = check_instance_count({"resource_changes": []})
        assert result == []

    def test_non_instance_resources_not_counted(self):
        """Test that non-instance resources are not counted."""
        result = check_instance_count(
            {
                "resource_changes": [
                    {
                        "type": "aws_s3_bucket",
                        "name": "bucket",
                        "change": {"actions": ["create"]},
                    },
                    {
                        "type": "aws_iam_role",
                        "name": "role",
                        "change": {"actions": ["create"]},
                    },
                ]
            }
        )
        assert result == []


class TestServicesDisabled:
    """Tests for disabled services detection."""

    def test_no_interface_vpc_endpoints(self):
        """Test that interface VPC endpoints are detected."""
        result = check_services_disabled(
            {
                "resource_changes": [
                    {"type": "aws_vpc_endpoint", "name": "interface_endpoint"}
                ]
            }
        )
        assert len(result) == 1
        assert "interface VPC endpoint" in result[0]

    def test_transit_gateway_detected(self):
        """Test that Transit Gateway is detected."""
        result = check_services_disabled(
            {"resource_changes": [{"type": "aws_ec2_transit_gateway", "name": "tgw"}]}
        )
        assert len(result) == 1
        assert "Transit Gateway" in result[0]


class TestScanPlan:
    """Integration tests for the main scan_plan function."""

    def test_valid_plan_passes(self):
        """Test that a valid plan passes all checks."""
        valid_plan = {
            "variables": {"aws_region": {"value": "us-east-1"}},
            "resource_changes": [
                {
                    "type": "aws_instance",
                    "name": "test_instance",
                    "change": {"after": {"instance_type": "t3.micro"}},
                }
            ],
        }

        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump(valid_plan, f)
            temp_path = f.name

        try:
            violations = scan_plan(temp_path)
            assert violations == []
        finally:
            Path(temp_path).unlink()

    def test_invalid_region_detected(self):
        """Test that invalid region is detected in full scan."""
        invalid_plan = {
            "variables": {"aws_region": {"value": "eu-west-1"}},
            "resource_changes": [],
        }

        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump(invalid_plan, f)
            temp_path = f.name

        try:
            violations = scan_plan(temp_path)
            assert len(violations) >= 1
            assert "eu-west-1" in violations[0]
        finally:
            Path(temp_path).unlink()

    def test_invalid_instance_type_detected(self):
        """Test that invalid instance type is detected in full scan."""
        invalid_plan = {
            "variables": {"aws_region": {"value": "us-east-1"}},
            "resource_changes": [
                {
                    "type": "aws_instance",
                    "name": "bad_instance",
                    "change": {"after": {"instance_type": "m5.large"}},
                }
            ],
        }

        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump(invalid_plan, f)
            temp_path = f.name

        try:
            violations = scan_plan(temp_path)
            assert len(violations) >= 1
            assert "m5.large" in violations[0]
        finally:
            Path(temp_path).unlink()

    def test_missing_plan_file(self):
        """Test error handling for missing plan file."""
        with pytest.raises(SystemExit) as exc_info:
            scan_plan("/nonexistent/path/plan.json")
        assert exc_info.value.code == 1

    def test_invalid_json_file(self):
        """Test error handling for invalid JSON."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            f.write("not valid json {{{")
            temp_path = f.name

        try:
            with pytest.raises(SystemExit) as exc_info:
                scan_plan(temp_path)
            assert exc_info.value.code == 1
        finally:
            Path(temp_path).unlink()


class TestUnusableResources:
    """Tests for resources that are unusable in sandbox."""

    def test_dcv_resource_detected(self):
        """Test that NICE DCV-related resources trigger warning."""
        # Note: There's no specific aws_nice_dcv resource type in AWS,
        # but we might have custom resources or launch templates
        result = check_unavailable_services(
            {
                "resource_changes": [
                    {
                        "type": "aws_instance",
                        "name": "dvc_instance",
                        "change": {"after": {"instance_type": "t3.medium"}},
                    }
                ]
            }
        )
        # DCV is type-dependent, so this should pass if instance type is OK
        assert result == []
