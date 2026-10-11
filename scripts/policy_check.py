#!/usr/bin/env python3
"""
Policy check script for HPC Platform Operations Test Bed.
Scans Terraform plan JSON for disallowed instance types, regions, and unavailable services.
"""

import json
import sys
from pathlib import Path

# Allowed instance types per sandbox limits (t2/t3/t3a/t4g micro, small, medium)
ALLOWED_INSTANCE_TYPES = {
    "t2.micro",
    "t2.small",
    "t2.medium",
    "t3.micro",
    "t3.small",
    "t3.medium",
    "t3a.micro",
    "t3a.small",
    "t3a.medium",
    "t4g.micro",
    "t4g.small",
    "t4g.medium",
}

# Allowed regions per sandbox limits
ALLOWED_REGIONS = {"us-east-1", "us-west-2"}

# Unavailable services per sandbox limitations
# These are documented in the ADRs and design.md
UNAVAILABLE_SERVICES = {
    "aws_pcs": "AWS ParallelCluster is not available in sandbox (use self-managed Slurm)",
    "aws_res": "AWS Renewable Energy Service is not available (see ADR)",
    "transit_gateway": "Transit Gateway is not available (see ADR)",
    "direct_connect": "Direct Connect is not available (see ADR)",
    "private_link": "PrivateLink is not available (see ADR)",
    "efa": "EFA networking is not available (see ADR)",
    "fsx_lustre": "FSx for Lustre may be blocked or unaffordable (see sandbox-notes.md)",
    "nice_dcv": "NICE DCV may be blocked or require licensing (see ADR)",
    "aws_res": "AWS Resource Scheduler is DESIGN-ONLY (see ADR)",
}


def check_instance_types(plan_data):
    """Check for disallowed instance types in the plan."""
    violations = []

    if "resource_changes" not in plan_data:
        return violations

    for resource in plan_data["resource_changes"]:
        if resource.get("type") != "aws_instance":
            continue

        # Get the instance type from the plan
        change = resource.get("change", {})
        after = change.get("after", {})
        instance_type = after.get("instance_type", "")

        if instance_type and instance_type not in ALLOWED_INSTANCE_TYPES:
            resource_name = resource.get("name", "unknown")
            violations.append(
                f"Instance type violation: {resource_name} uses '{instance_type}' "
                f"which is not in the allowed list."
            )

    return violations


def check_region(plan_data, config_region):
    """Check if the configured region is allowed."""
    violations = []

    if config_region not in ALLOWED_REGIONS:
        violations.append(
            f"Region violation: '{config_region}' is not in the allowed regions "
            f"(us-east-1, us-west-2)."
        )

    return violations


def check_unavailable_services(plan_data):
    """Check for references to unavailable services."""
    violations = []

    if "resource_changes" not in plan_data:
        return violations

    for resource in plan_data["resource_changes"]:
        resource_type = resource.get("type", "")
        resource_name = resource.get("name", "unknown")

        # Check for services that are unavailable in sandbox
        if resource_type == "aws_pcs_cluster":
            violations.append(
                f"Unavailable service: {resource_name} uses aws_pcs_cluster "
                f"which is not available (AWS ParallelCluster). See ADR for PCS."
            )
        elif resource_type == "aws_ec2_traffic_mirror_session":
            violations.append(
                f"Unavailable service: {resource_name} uses EFA-related resources "
                f"which are not available in sandbox."
            )
        elif resource_type == "aws_vpc_endpoint_service":
            violations.append(
                f"Unavailable service: {resource_name} uses PrivateLink which "
                f"is not available. See ADR."
            )

    return violations


def check_instance_count(plan_data):
    """Check if instance count exceeds sandbox limit (9)."""
    violations = []
    instance_count = 0

    if "resource_changes" not in plan_data:
        return violations

    for resource in plan_data["resource_changes"]:
        if resource.get("type") == "aws_instance":
            # Count resources that will be created or changed
            change = resource.get("change", {})
            action = change.get("actions", [])

            if "create" in action or "update" in action:
                instance_count += 1

    # Include existing instances (in state) - approximate by checking
    # This is a simplified check; a full state inspection would be better
    if "planned_values" in plan_data and "root_module" in plan_data["planned_values"]:
        planned_resources = plan_data["planned_values"]["root_module"].get(
            "resources", []
        )
        for resource in planned_resources:
            if resource.get("type") == "aws_instance":
                instance_count += 1

    if instance_count > 9:
        violations.append(
            f"Instance count violation: {instance_count} instances planned, "
            f"exceeds sandbox limit of 9."
        )

    return violations


def check_services_disabled(plan_data):
    """Check for services that should be disabled in sandbox."""
    violations = []

    if "resource_changes" not in plan_data:
        return violations

    for resource in plan_data["resource_changes"]:
        resource_type = resource.get("type", "")
        resource_name = resource.get("name", "unknown")

        # Check for interface VPC endpoints (not allowed)
        if resource_type in ("aws_vpc_endpoint",):
            violations.append(
                f"interface VPC endpoint {resource_name} is not allowed. "
                f"Only gateway endpoints are permitted per sandbox design."
            )

        # Check for Transit Gateway (not allowed)
        if resource_type.startswith("aws_ec2_transit_gateway"):
            violations.append(
                f"Transit Gateway {resource.get('name', 'unknown')} is not allowed. "
                f"See ADR for Transit Gateway design."
            )

    return violations


def scan_plan(plan_file_path):
    """Scan a Terraform plan JSON file for policy violations."""
    try:
        with open(plan_file_path, "r") as f:
            plan_data = json.load(f)
    except FileNotFoundError:
        print(f"Error: Plan file not found: {plan_file_path}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in plan file: {e}")
        sys.exit(1)

    # Get configured region (from variables if available)
    config_region = "us-east-1"  # Default
    if "variables" in plan_data:
        for var_name, var_data in plan_data["variables"].items():
            if var_name == "aws_region" and "value" in var_data:
                config_region = var_data["value"]

    violations = []

    # Run all checks
    violations.extend(check_instance_types(plan_data))
    violations.extend(check_region(plan_data, config_region))
    violations.extend(check_unavailable_services(plan_data))
    violations.extend(check_instance_count(plan_data))
    violations.extend(check_services_disabled(plan_data))

    return violations


def main():
    """Main entry point."""
    # Default plan file path
    default_plan = "terraform.tfplan.json"

    # Accept plan file as command line argument or use default
    plan_file = sys.argv[1] if len(sys.argv) > 1 else default_plan
    plan_path = Path(plan_file)

    if not plan_path.exists():
        print(f"Error: Plan file not found: {plan_file}")
        sys.exit(1)

    print(f"Scanning policy for: {plan_file}")
    print("-" * 60)

    violations = scan_plan(plan_file)

    if violations:
        print("\nPOLICY VIOLATIONS FOUND:")
        for v in violations:
            print(f"  ❌ {v}")
        print(f"\nTotal: {len(violations)} violation(s)")
        sys.exit(1)
    else:
        print("\n✓ All policy checks passed!")
        sys.exit(0)


if __name__ == "__main__":
    main()
