#!/usr/bin/env python3
"""
Evidence collector for HPC Platform Operations Test Bed.

Gathers IAM, KMS, CloudTrail, Config, and other security-related information
for audit and accreditation purposes.

Output: evidence/ directory with timestamped session folders containing
JSON exports and a manifest with SHA-256 hashes.
"""

import argparse
import hashlib
import json
import subprocess
from datetime import datetime
from pathlib import Path

# Evidence directory
EVIDENCE_DIR = Path("evidence")


def sha256_file(filepath):
    """Calculate SHA-256 hash of a file."""
    sha256_hash = hashlib.sha256()
    with open(filepath, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def ensure_evidence_dir():
    """Ensure evidence directory exists and return new session directory."""
    EVIDENCE_DIR.mkdir(exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    session_id = subprocess.run(
        ["aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"],
        capture_output=True,
        text=True,
    ).stdout.strip()

    evidence_dir = EVIDENCE_DIR / f"session_{timestamp}_{session_id}"
    evidence_dir.mkdir(exist_ok=True)

    return evidence_dir


def run_aws_command(args, output_file):
    """Run an AWS CLI command and save output to file."""
    try:
        result = subprocess.run(["aws"] + args, capture_output=True, text=True)

        if result.returncode == 0:
            with open(output_file, "w") as f:
                f.write(result.stdout)
            return True
        else:
            with open(output_file, "w") as f:
                f.write(f"Error: {result.stderr}")
            return False
    except Exception as e:
        with open(output_file, "w") as f:
            f.write(f"Exception: {e}")
        return False


def collect_iam_info(evidence_dir):
    """Collect IAM information."""
    print("Collecting IAM information...")
    iam_dir = evidence_dir / "iam"
    iam_dir.mkdir(exist_ok=True)

    # IAM summary
    run_aws_command(["iam", "get-account-summary"], iam_dir / "account_summary.json")

    # List users
    run_aws_command(["iam", "list-users"], iam_dir / "users.json")

    # List roles
    run_aws_command(["iam", "list-roles"], iam_dir / "roles.json")

    # List policies
    run_aws_command(
        ["iam", "list-policies", "--scope", "Local"], iam_dir / "policies.json"
    )

    # List access keys
    run_aws_command(["iam", "list-access-keys"], iam_dir / "access_keys.json")


def collect_kms_info(evidence_dir):
    """Collect KMS information."""
    print("Collecting KMS information...")
    kms_dir = evidence_dir / "kms"
    kms_dir.mkdir(exist_ok=True)

    # List keys
    run_aws_command(["kms", "list-keys"], kms_dir / "keys.json")

    # Describe keys
    result = subprocess.run(
        ["aws", "kms", "list-keys", "--query", "Keys[].KeyId", "--output", "text"],
        capture_output=True,
        text=True,
    )

    if result.returncode == 0:
        key_ids = result.stdout.strip().split()
        for key_id in key_ids:
            run_aws_command(
                ["kms", "describe-key", "--key-id", key_id],
                kms_dir / f"key_{key_id}.json",
            )
            run_aws_command(
                ["kms", "get-key-rotation-status", "--key-id", key_id],
                kms_dir / f"rotation_{key_id}.json",
            )


def collect_cloudtrail_info(evidence_dir):
    """Collect CloudTrail information."""
    print("Collecting CloudTrail information...")
    cloudtrail_dir = evidence_dir / "cloudtrail"
    cloudtrail_dir.mkdir(exist_ok=True)

    # List trails
    run_aws_command(["cloudtrail", "list-trails"], cloudtrail_dir / "trails.json")

    # Describe trails
    result = subprocess.run(
        [
            "aws",
            "cloudtrail",
            "list-trails",
            "--query",
            "Trails[].Name",
            "--output",
            "text",
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode == 0:
        trail_names = result.stdout.strip().split()
        for name in trail_names:
            run_aws_command(
                ["cloudtrail", "describe-trails", "--trail-name-list", name],
                cloudtrail_dir / f"trail_{name}.json",
            )


def collect_config_info(evidence_dir):
    """Collect AWS Config information."""
    print("Collecting Config information...")
    config_dir = evidence_dir / "config"
    config_dir.mkdir(exist_ok=True)

    # Describe recorders
    run_aws_command(
        ["configservice", "describe-configuration-recorders"],
        config_dir / "recorders.json",
    )

    # Describe delivery channels
    run_aws_command(
        ["configservice", "describe-delivery-channels"],
        config_dir / "delivery_channels.json",
    )

    # List config rules
    run_aws_command(
        ["configservice", "describe-config-rules"], config_dir / "rules.json"
    )


def collect_security_hub_info(evidence_dir):
    """Collect Security Hub information."""
    print("Collecting Security Hub information...")
    hub_dir = evidence_dir / "securityhub"
    hub_dir.mkdir(exist_ok=True)

    # Get hub status
    run_aws_command(["securityhub", "get-hub"], hub_dir / "hub.json")

    # Get findings
    run_aws_command(["securityhub", "get-findings"], hub_dir / "findings.json")


def collect_guardduty_info(evidence_dir):
    """Collect GuardDuty information."""
    print("Collecting GuardDuty information...")
    guardduty_dir = evidence_dir / "guardduty"
    guardduty_dir.mkdir(exist_ok=True)

    # List detectors
    run_aws_command(["guardduty", "list-detectors"], guardduty_dir / "detectors.json")

    # Get detector
    result = subprocess.run(
        [
            "aws",
            "guardduty",
            "list-detectors",
            "--query",
            "DetectorIds[0]",
            "--output",
            "text",
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode == 0 and result.stdout.strip():
        detector_id = result.stdout.strip()
        run_aws_command(
            ["guardduty", "get-detector", "--detector-id", detector_id],
            guardduty_dir / "detector.json",
        )


def collect_ec2_info(evidence_dir):
    """Collect EC2 information."""
    print("Collecting EC2 information...")
    ec2_dir = evidence_dir / "ec2"
    ec2_dir.mkdir(exist_ok=True)

    # Describe instances
    run_aws_command(["ec2", "describe-instances"], ec2_dir / "instances.json")

    # Describe security groups
    run_aws_command(
        ["ec2", "describe-security-groups"], ec2_dir / "security_groups.json"
    )

    # Describe volumes
    run_aws_command(["ec2", "describe-volumes"], ec2_dir / "volumes.json")


def create_manifest(evidence_dir):
    """Create manifest with file hashes."""
    print("Creating manifest...")
    manifest = {"generated_at": datetime.now().isoformat(), "files": []}

    for filepath in evidence_dir.rglob("*"):
        if filepath.is_file() and filepath.suffix == ".json":
            rel_path = str(filepath.relative_to(evidence_dir))
            file_hash = sha256_file(filepath)
            manifest["files"].append({"path": rel_path, "sha256": file_hash})

    manifest["files"].sort(key=lambda x: x["path"])

    manifest_path = evidence_dir / "manifest.json"
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    return manifest


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Generate evidence pack for audit and accreditation"
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default=None,
        help="Output directory for evidence pack",
    )

    args = parser.parse_args()

    if args.output_dir:
        evidence_dir = Path(args.output_dir)
        evidence_dir.mkdir(parents=True, exist_ok=True)
    else:
        evidence_dir = ensure_evidence_dir()

    print(f"Generating evidence pack in {evidence_dir}")
    print("=" * 60)

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

    print("=" * 60)
    print(f"✓ Evidence pack generated in {evidence_dir}")
    print(f"  Files: {len(manifest['files'])}")
    print(f"  Session: {evidence_dir.name}")


if __name__ == "__main__":
    main()
