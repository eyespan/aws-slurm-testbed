#!/usr/bin/env python3
"""
Deployment lifecycle script for HPC Platform Operations Test Bed.

Handles:
- `up`: validates preflight, runs terraform apply, exports evidence, destroys tagged resources on failure
- `down`: exports evidence, runs terraform destroy
"""

import argparse
import json
import os
import subprocess
import sys
import uuid
from datetime import datetime
from pathlib import Path

# Terraform directory
TERRAFORM_DIR = Path("terraform/bootstrap")

# Evidence directory
EVIDENCE_DIR = Path("evidence")


def ensure_evidence_dir():
    """Ensure evidence directory exists."""
    EVIDENCE_DIR.mkdir(exist_ok=True)
    return EVIDENCE_DIR


def generate_session_id():
    """Generate a unique session ID."""
    return str(uuid.uuid4())[:8]


def run_preflight():
    """Run preflight checks."""
    print("Running preflight checks...")
    result = subprocess.run(
        ["python3", "scripts/preflight.py"], capture_output=True, text=True
    )

    if result.returncode != 0:
        print("Preflight checks failed!")
        print(result.stdout)
        if result.stderr:
            print(result.stderr)
        return False

    print(result.stdout)
    return True


def export_evidence(action="deploy"):
    """Export evidence before operations."""
    ensure_evidence_dir()

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    session_id = generate_session_id()
    evidence_dir = EVIDENCE_DIR / f"{action}_{timestamp}_{session_id}"
    evidence_dir.mkdir(exist_ok=True)

    # Export current state
    try:
        result = subprocess.run(
            ["aws", "ec2", "describe-instances"], capture_output=True, text=True
        )

        if result.returncode == 0:
            with open(evidence_dir / "instances.json", "w") as f:
                json.dump(json.loads(result.stdout), f, indent=2)

        # Export security-related resources
        result = subprocess.run(
            ["aws", "ec2", "describe-security-groups"], capture_output=True, text=True
        )

        if result.returncode == 0:
            with open(evidence_dir / "security_groups.json", "w") as f:
                json.dump(json.loads(result.stdout), f, indent=2)

        # Export VPC info
        result = subprocess.run(
            ["aws", "ec2", "describe-vpcs"], capture_output=True, text=True
        )

        if result.returncode == 0:
            with open(evidence_dir / "vpcs.json", "w") as f:
                json.dump(json.loads(result.stdout), f, indent=2)

        print(f"✓ Evidence exported to {evidence_dir}")
    except Exception as e:
        print(f"⚠ Evidence export warning: {e}")

    return session_id, evidence_dir


def terraform_apply(session_id):
    """Run terraform apply with auto-approve."""
    print(f"Applying terraform changes (session: {session_id})...")

    env = os.environ.copy()
    env["TF_VAR_session"] = session_id

    result = subprocess.run(
        ["terraform", "apply", "-auto-approve"],
        capture_output=True,
        text=True,
        cwd=str(TERRAFORM_DIR),
        env=env,
    )

    if result.returncode != 0:
        print("Terraform apply failed!")
        print(result.stdout)
        if result.stderr:
            print(result.stderr)
        return False

    print(result.stdout)
    return True


def terraform_destroy(session_id):
    """Run terraform destroy with auto-approve."""
    print(f"Destroying terraform resources (session: {session_id})...")

    env = os.environ.copy()
    env["TF_VAR_session"] = session_id

    result = subprocess.run(
        ["terraform", "destroy", "-auto-approve"],
        capture_output=True,
        text=True,
        cwd=str(TERRAFORM_DIR),
        env=env,
    )

    if result.returncode != 0:
        print("Terraform destroy failed!")
        print(result.stdout)
        if result.stderr:
            print(result.stderr)
        return False

    print(result.stdout)
    return True


def destroy_tagged_resources(session_id):
    """Destroy resources tagged with the session ID."""
    print(f"Destroying resources tagged with session: {session_id}...")

    try:
        # Get EC2 instances with the session tag
        result = subprocess.run(
            [
                "aws",
                "ec2",
                "describe-instances",
                "--filters",
                f"Name=tag:Session,Values={session_id}",
                "--query",
                "Reservations[].Instances[].InstanceId",
                "--output",
                "text",
            ],
            capture_output=True,
            text=True,
        )

        instance_ids = result.stdout.strip().split()

        if instance_ids:
            print(f"Found {len(instance_ids)} instances to terminate...")

            # Terminate instances
            subprocess.run(
                ["aws", "ec2", "terminate-instances", "--instance-ids"] + instance_ids,
                check=True,
            )

            # Wait for termination
            print("Waiting for instances to terminate...")
            subprocess.run(
                ["aws", "ec2", "wait", "instance-terminated", "--instance-ids"]
                + instance_ids,
                check=True,
            )

        # Clean up EBS volumes with session tag
        result = subprocess.run(
            [
                "aws",
                "ec2",
                "describe-volumes",
                "--filters",
                f"Name=tag:Session,Values={session_id}",
                "--query",
                "Volumes[].VolumeId",
                "--output",
                "text",
            ],
            capture_output=True,
            text=True,
        )

        volume_ids = result.stdout.strip().split()

        if volume_ids:
            print(f"Found {len(volume_ids)} volumes to delete...")

            for volume_id in volume_ids:
                subprocess.run(
                    ["aws", "ec2", "delete-volume", "--volume-id", volume_id],
                    check=True,
                )

        # Clean up security groups with session tag (non-default only)
        result = subprocess.run(
            [
                "aws",
                "ec2",
                "describe-security-groups",
                "--filters",
                f"Name=tag:Session,Values={session_id}",
                "--query",
                "SecurityGroups[?GroupName != 'default'].GroupId",
                "--output",
                "text",
            ],
            capture_output=True,
            text=True,
        )

        sg_ids = result.stdout.strip().split()

        if sg_ids:
            print(f"Found {len(sg_ids)} security groups to delete...")

            for sg_id in sg_ids:
                subprocess.run(
                    ["aws", "ec2", "delete-security-group", "--group-id", sg_id],
                    check=True,
                )

        print("✓ Tagged resources cleaned up")
        return True

    except subprocess.CalledProcessError as e:
        print(f"⚠ Resource cleanup warning: {e}")
        return True  # Don't fail the deployment for cleanup issues

    except Exception as e:
        print(f"⚠ Resource cleanup warning: {e}")
        return True  # Don't fail the deployment for cleanup issues


def cmd_up(args):
    """Handle 'up' command."""
    # Generate session ID
    session_id = generate_session_id()
    print(f"Session ID: {session_id}")

    # Run preflight
    if not run_preflight():
        print("Preflight checks failed. Aborting.")
        sys.exit(1)

    # Export evidence before apply
    print("\nExporting evidence before apply...")
    export_evidence("apply_before")

    # Apply terraform
    if not terraform_apply(session_id):
        print("\nApply failed. Destroying tagged resources...")
        destroy_tagged_resources(session_id)
        sys.exit(1)

    # Export evidence after apply
    print("\nExporting evidence after apply...")
    export_evidence("apply_after")

    print("\n✓ Deployment complete!")


def cmd_down(args):
    """Handle 'down' command."""
    # Generate session ID
    session_id = generate_session_id()
    print(f"Session ID: {session_id}")

    # Export evidence before destroy
    print("\nExporting evidence before destroy...")
    export_evidence("destroy_before")

    # Destroy terraform resources
    if not terraform_destroy(session_id):
        print("Destroy failed!")
        sys.exit(1)

    # Export evidence after destroy
    print("\nExporting evidence after destroy...")
    export_evidence("destroy_after")

    print("\n✓ Destruction complete!")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="HPC Platform Operations Test Bed Deployment Script"
    )

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # 'up' command
    subparsers.add_parser("up", help="Apply infrastructure")

    # 'down' command
    subparsers.add_parser("down", help="Destroy infrastructure")

    args = parser.parse_args()

    if args.command == "up":
        cmd_up(args)
    elif args.command == "down":
        cmd_down(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
