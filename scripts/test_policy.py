#!/usr/bin/env python3
"""Test script to verify policy check implementation without pytest."""

import sys

sys.path.insert(0, ".")

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


def test_all():
    """Run all tests and report results."""
    passed = 0
    failed = 0

    def check(test_name, condition, message=""):
        nonlocal passed, failed
        if condition:
            passed += 1
            print(f"  ✓ {test_name}")
        else:
            failed += 1
            print(f"  ✗ {test_name}: {message}")

    print("=" * 60)
    print("Testing Instance Type Validation")
    print("=" * 60)

    # Test allowed instance types
    for instance_type in ALLOWED_INSTANCE_TYPES:
        result = check_instance_types(
            {
                "resource_changes": [
                    {
                        "type": "aws_instance",
                        "name": "test",
                        "change": {"after": {"instance_type": instance_type}},
                    }
                ]
            }
        )
        check(f"Allowed: {instance_type}", result == [])

    # Test disallowed instance type
    result = check_instance_types(
        {
            "resource_changes": [
                {
                    "type": "aws_instance",
                    "name": "bad",
                    "change": {"after": {"instance_type": "m5.large"}},
                }
            ]
        }
    )
    check("Disallowed: m5.large detected", len(result) > 0, f"Got: {result}")

    print()
    print("=" * 60)
    print("Testing Region Validation")
    print("=" * 60)

    # Test allowed regions
    for region in ALLOWED_REGIONS:
        result = check_region({}, region)
        check(f"Region: {region} allowed", result == [])

    # Test disallowed region
    result = check_region({}, "eu-west-1")
    check("Region: eu-west-1 detected", len(result) > 0, f"Got: {result}")

    print()
    print("=" * 60)
    print("Testing Unavailable Services")
    print("=" * 60)

    # Test PCS cluster detection
    result = check_unavailable_services(
        {"resource_changes": [{"type": "aws_pcs_cluster", "name": "pcs"}]}
    )
    check("PCS cluster detected", len(result) > 0, f"Got: {result}")

    # Test EFA detection
    result = check_unavailable_services(
        {
            "resource_changes": [
                {"type": "aws_ec2_traffic_mirror_session", "name": "efa"}
            ]
        }
    )
    check("EFA detected", len(result) > 0, f"Got: {result}")

    print()
    print("=" * 60)
    print("Testing Instance Count")
    print("=" * 60)

    # Test under limit
    result = check_instance_count(
        {
            "resource_changes": [
                {
                    "type": "aws_instance",
                    "name": f"n{i}",
                    "change": {"actions": ["create"]},
                }
                for i in range(5)
            ]
        }
    )
    check("5 instances under limit", result == [])

    # Test over limit
    result = check_instance_count(
        {
            "resource_changes": [
                {
                    "type": "aws_instance",
                    "name": f"n{i}",
                    "change": {"actions": ["create"]},
                }
                for i in range(10)
            ]
        }
    )
    check("10 instances over limit detected", len(result) > 0, f"Got: {result}")

    print()
    print("=" * 60)
    print("Testing Services Disabled")
    print("=" * 60)

    # Test VPC endpoint detection
    result = check_services_disabled(
        {"resource_changes": [{"type": "aws_vpc_endpoint", "name": "endpoint"}]}
    )
    check("VPC endpoint detected", len(result) > 0, f"Got: {result}")

    # Test Transit Gateway detection
    result = check_services_disabled(
        {"resource_changes": [{"type": "aws_ec2_transit_gateway", "name": "tgw"}]}
    )
    check("Transit Gateway detected", len(result) > 0, f"Got: {result}")

    print()
    print("=" * 60)
    print("Testing Full Plan Scans")
    print("=" * 60)

    # Test valid plan
    result = scan_plan("test_valid_plan.json")
    check("Valid plan passes", result == [], f"Got: {result}")

    # Test invalid plan
    result = scan_plan("test_invalid_plan.json")
    check("Invalid plan fails", len(result) > 0, f"Got: {result}")

    print()
    print("=" * 60)
    print(f"SUMMARY: {passed} passed, {failed} failed")
    print("=" * 60)

    return failed == 0


if __name__ == "__main__":
    success = test_all()
    sys.exit(0 if success else 1)
