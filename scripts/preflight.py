#!/usr/bin/env python3
"""
Preflight verification script for HPC Platform Operations Test Bed.

Verifies:
- AWS identity is 'cloud_user' (via STS get-caller-identity)
- Region is from allowed list (us-east-1, us-west-2)
- Running instance count is within budget (max 9 instances)
- Uses existing policy_check.py for plan validation
"""

import subprocess
import sys
from pathlib import Path

import boto3

# Allowed regions per sandbox limits
ALLOWED_REGIONS = {"us-east-1", "us-west-2"}

# Maximum running instance count (sandbox limit)
MAX_INSTANCE_COUNT = 9


def check_aws_identity():
    """Verify AWS identity is 'cloud_user'."""
    try:
        session = boto3.Session(profile_name="hpc-testbed")

        sts = boto3.client(
            "sts",
            region_name=session.region_name,
            aws_access_key_id=session.get_credentials().access_key,
            aws_secret_access_key=session.get_credentials().secret_key,
        )
        response = sts.get_caller_identity()
        arn = response.get("Arn", "")
        user_name = arn.split("/")[-1] if "/" in arn else arn

        if user_name != "cloud_user":
            print(f"❌ Identity check failed: expected 'cloud_user', got '{user_name}'")
            return False

        print(f"✓ Identity check passed: {user_name}")
        return True
    except Exception as e:
        print(f"❌ Identity check failed: {e}")
        return False


def check_region():
    """Verify region is from allowed list."""
    try:
        # Get region from boto3 session
        session = boto3.Session(profile_name="hpc-testbed")
        region = session.region_name

        if not region:
            # Try to get from environment or config
            result = subprocess.run(
                ["aws", "configure", "get", "region"], capture_output=True, text=True
            )
            region = result.stdout.strip()

        if region not in ALLOWED_REGIONS:
            print(
                f"❌ Region check failed: '{region}' is not in allowed regions {ALLOWED_REGIONS}"
            )
            return False

        print(f"✓ Region check passed: {region}")
        return True
    except Exception as e:
        print(f"❌ Region check failed: {e}")
        return False


def count_running_instances():
    """Count running EC2 instances in the current region."""
    try:
        session = boto3.Session(profile_name="hpc-testbed")
        region = session.region_name

        ec2 = boto3.client(
            "ec2",
            region_name=region,
            aws_access_key_id=session.get_credentials().access_key,
            aws_secret_access_key=session.get_credentials().secret_key,
        )

        # Describe instances with filters for running state
        response = ec2.describe_instances(
            Filters=[{"Name": "instance-state-name", "Values": ["running", "pending"]}]
        )

        total_count = 0
        for reservation in response.get("Reservations", []):
            total_count += len(reservation.get("Instances", []))

        return total_count
    except Exception as e:
        print(f"❌ Failed to count instances: {e}")
        return None


def check_instance_budget():
    """Verify running instance count is within budget."""
    instance_count = count_running_instances()

    if instance_count is None:
        return False

    if instance_count > MAX_INSTANCE_COUNT:
        print(
            f"❌ Instance budget check failed: {instance_count} instances running, "
            f"exceeds maximum of {MAX_INSTANCE_COUNT}"
        )
        return False

    available = MAX_INSTANCE_COUNT - instance_count
    print(
        f"✓ Instance budget check passed: {instance_count}/{MAX_INSTANCE_COUNT} instances running "
        f"({available} available)"
    )
    return True


def check_policy():
    """Run policy check on Terraform plan."""
    try:
        # Check if plan file exists
        plan_file = Path("terraform.tfplan.json")

        if not plan_file.exists():
            # Try to generate plan first
            print("Note: No existing plan file found, skipping policy check")
            return True

        # Run policy check
        result = subprocess.run(
            ["python3", "scripts/policy_check.py", str(plan_file)],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            print("❌ Policy check failed:")
            print(result.stdout)
            print(result.stderr)
            return False

        print("✓ Policy check passed")
        return True
    except Exception as e:
        print(f"❌ Policy check error: {e}")
        return False


def main():
    """Main entry point."""
    print("=" * 60)
    print("HPC Platform Operations Test Bed - Preflight Checks")
    print("=" * 60)

    results = []

    # Run all checks
    results.append(("AWS Identity", check_aws_identity()))
    results.append(("AWS Region", check_region()))
    results.append(("Instance Budget", check_instance_budget()))
    results.append(("Policy Check", check_policy()))

    # Summary
    print("=" * 60)
    print("Preflight Summary")
    print("=" * 60)

    all_passed = True
    for name, passed in results:
        status = "✓ PASS" if passed else "❌ FAIL"
        print(f"{status}: {name}")
        if not passed:
            all_passed = False

    if all_passed:
        print("\n✓ All preflight checks passed!")
        sys.exit(0)
    else:
        print("\n❌ Some preflight checks failed!")
        sys.exit(1)


if __name__ == "__main__":
    main()
