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

# Full stack root module (bootstrap is a child module under terraform/)
TERRAFORM_DIR = Path("terraform")

# Evidence directory
EVIDENCE_DIR = Path("evidence")


def ensure_evidence_dir():
    """Ensure evidence directory exists."""
    EVIDENCE_DIR.mkdir(exist_ok=True)
    return EVIDENCE_DIR


def generate_session_id():
    """Generate a unique session ID (8 hex chars)."""
    return str(uuid.uuid4())[:8]


def _session_file() -> Path:
    """Persisted session id so subsequent make up/down reuse the same stack."""
    return Path(".hpc-session")


def resolve_session_id(for_destroy: bool = False) -> str:
    """
    Reuse a stable session id so terraform does not replace the whole stack.

    Almost every resource name is ``${project}-${env}-${session}-...``. A new
    random session on every ``make up`` forces destroy+create of VPC, EFS, KMS,
    Image Builder, EC2, etc.

    Order of preference:
      1. Explicit SESSION / TF_VAR_session environment variable
      2. ``.hpc-session`` file written by a previous successful apply
      3. Value already in terraform state (var.session), if any
      4. New random id (first deploy only) — not used for destroy
    """
    for key in ("SESSION", "TF_VAR_session"):
        val = os.environ.get(key, "").strip()
        if val:
            print(f"Using session from ${key}: {val}")
            return val

    sf = _session_file()
    if sf.exists():
        val = sf.read_text().strip()
        if val:
            print(f"Using session from {sf}: {val}")
            return val

    # Try terraform state (works after at least one apply with matching backend)
    try:
        result = subprocess.run(
            [
                "terraform",
                f"-chdir={TERRAFORM_DIR}",
                "state",
                "pull",
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode == 0 and result.stdout.strip():
            state = json.loads(result.stdout)
            # Root module variables are not always in state; scan resource names
            for mod in state.get("resources", []) or []:
                for inst in mod.get("instances", []) or []:
                    attrs = inst.get("attributes") or {}
                    tags = attrs.get("tags") or attrs.get("tags_all") or {}
                    if isinstance(tags, dict) and tags.get("Session"):
                        val = str(tags["Session"]).strip()
                        if val:
                            print(f"Using session from terraform state tags: {val}")
                            sf.write_text(val + "\n")
                            return val
                    name = attrs.get("name") or ""
                    # Names look like hpc-testbed-dev-<session>-...
                    if isinstance(name, str) and name.startswith("hpc-testbed-"):
                        parts = name.split("-")
                        # hpc, testbed, dev, SESSION, ...
                        if len(parts) >= 4 and parts[0] == "hpc" and parts[1] == "testbed":
                            val = parts[3]
                            if val and val not in ("dev", "prod", "default"):
                                print(f"Using session inferred from resource name: {val}")
                                sf.write_text(val + "\n")
                                return val
    except Exception as e:
        print(f"⚠ Could not read session from state: {e}")

    if for_destroy:
        print(
            "No session found for destroy. Set SESSION=... to match the stack "
            "(see resource names or .hpc-session).",
            file=sys.stderr,
        )
        sys.exit(1)

    val = generate_session_id()
    print(f"New session (first deploy): {val}")
    return val


def persist_session_id(session_id: str) -> None:
    _session_file().write_text(session_id.strip() + "\n")
    print(f"Persisted session to {_session_file()}")


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


def terraform_init():
    """Initialize terraform in the root module directory."""
    print(f"Initializing terraform in {TERRAFORM_DIR}...")
    result = subprocess.run(
        ["terraform", "init", "-input=false"],
        capture_output=True,
        text=True,
        cwd=str(TERRAFORM_DIR),
    )
    if result.returncode != 0:
        print("Terraform init failed!")
        print(result.stdout)
        if result.stderr:
            print(result.stderr)
        return False
    print(result.stdout)
    return True


# Phase targets: foundation has no EC2 instances; instances need AMI in SSM.
FOUNDATION_TARGETS = [
    "module.bootstrap",
    "module.network",
    "module.storage",
    "module.image_builder",
]

INSTANCE_TARGETS = [
    "module.controller",
    "module.login",
]


def terraform_apply(session_id, targets: list[str] | None = None, label: str = "full"):
    """Run terraform apply on the root stack (optionally -target list)."""
    if targets:
        print(f"Applying terraform phase '{label}' (session: {session_id})...")
        print(f"  targets: {', '.join(targets)}")
    else:
        print(f"Applying full terraform stack (session: {session_id})...")

    if not terraform_init():
        return False

    env = os.environ.copy()
    env["TF_VAR_session"] = session_id

    cmd = ["terraform", "apply", "-auto-approve", f"-var=session={session_id}"]
    for t in targets or []:
        cmd.extend(["-target", t])

    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=str(TERRAFORM_DIR),
        env=env,
    )

    if result.returncode != 0:
        print(f"Terraform apply ({label}) failed!")
        print(result.stdout)
        if result.stderr:
            print(result.stderr)
        return False

    print(result.stdout)
    return True


def check_ami_ready() -> bool:
    """Return True if SSM current AMI looks like a real custom AMI (ami-*)."""
    r = subprocess.run(
        [
            "aws",
            "ssm",
            "get-parameter",
            "--name",
            "/hpc-testbed/ami/compute/current",
            "--query",
            "Parameter.Value",
            "--output",
            "text",
        ],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        print(
            "SSM parameter /hpc-testbed/ami/compute/current not readable.\n"
            "Run: make foundation && make ami-build",
            file=sys.stderr,
        )
        return False
    ami = (r.stdout or "").strip()
    if not ami.startswith("ami-"):
        print(f"Unexpected AMI value in SSM: {ami!r}", file=sys.stderr)
        return False
    # Heuristic: AL2023 base often still works but we warn if never promoted
    print(f"SSM current AMI: {ami}")
    return True


def terraform_destroy(session_id):
    """Run terraform destroy on the full root stack with auto-approve."""
    print(f"Destroying full terraform stack (session: {session_id})...")

    if not terraform_init():
        return False

    env = os.environ.copy()
    env["TF_VAR_session"] = session_id

    result = subprocess.run(
        ["terraform", "destroy", "-auto-approve", f"-var=session={session_id}"],
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


def cmd_foundation(args):
    """
    Phase 1: VPC, subnets, SGs, EFS, KMS/logs, Image Builder pipeline.
    Does NOT create controller/login/debug EC2 instances.
    """
    session_id = resolve_session_id(for_destroy=False)
    print(f"Session ID: {session_id}")
    print("Phase 1/3: foundation (bootstrap + network + storage + image_builder)")

    if not run_preflight():
        print("Preflight checks failed. Aborting.")
        sys.exit(1)

    export_evidence("foundation_before")
    if not terraform_apply(session_id, targets=FOUNDATION_TARGETS, label="foundation"):
        print("\nFoundation apply failed.")
        sys.exit(1)

    persist_session_id(session_id)
    export_evidence("foundation_after")
    print("\n✓ Foundation complete (VPC, subnets, storage, Image Builder pipeline).")
    print("  Next: make ami-build   # build AMI and promote to SSM")
    print("  Then: make instances  # create controller / login / debug")
    print(f"  Session: {session_id} (persisted in .hpc-session)")


def cmd_instances(args):
    """
    Phase 3: controller + login (+ debug) after AMI is in SSM current.
    """
    session_id = resolve_session_id(for_destroy=False)
    print(f"Session ID: {session_id}")
    print("Phase 3/3: instances (controller + login/debug)")

    if not check_ami_ready():
        print(
            "\nRefusing to create instances without a usable AMI in SSM.\n"
            "  make foundation && make ami-build && make instances",
            file=sys.stderr,
        )
        sys.exit(1)

    if not run_preflight():
        print("Preflight checks failed. Aborting.")
        sys.exit(1)

    export_evidence("instances_before")
    if not terraform_apply(session_id, targets=INSTANCE_TARGETS, label="instances"):
        print("\nInstances apply failed.")
        sys.exit(1)

    persist_session_id(session_id)
    export_evidence("instances_after")
    print("\n✓ Instances complete (controller + login/debug).")
    print(f"  Session: {session_id}")


def cmd_up(args):
    """
    Full ordered deploy:
      1) foundation → 2) ami-build → 3) instances
    Use --skip-ami only if SSM already has the desired AMI.
    """
    session_id = resolve_session_id(for_destroy=False)
    print(f"Session ID: {session_id}")
    print("Ordered deploy: foundation → ami-build → instances")

    if not run_preflight():
        print("Preflight checks failed. Aborting.")
        sys.exit(1)

    export_evidence("apply_before")

    # 1) Foundation
    if not terraform_apply(session_id, targets=FOUNDATION_TARGETS, label="foundation"):
        print("\nFoundation failed.")
        sys.exit(1)
    persist_session_id(session_id)

    # 2) AMI build (unless skipped)
    if not getattr(args, "skip_ami", False):
        print("\nPhase 2/3: ami-build (Image Builder pipeline execution + SSM promote)")
        r = subprocess.run(
            [sys.executable, "scripts/ami_build.py"],
            cwd=str(Path.cwd()),
        )
        if r.returncode != 0:
            print("\nami-build failed. Instances were NOT created.")
            sys.exit(r.returncode)
    else:
        print("\nSkipping ami-build (--skip-ami); using existing SSM current AMI.")
        if not check_ami_ready():
            sys.exit(1)

    # 3) Instances
    if not terraform_apply(session_id, targets=INSTANCE_TARGETS, label="instances"):
        print("\nInstances apply failed.")
        sys.exit(1)

    # Optional remaining modules (fsx, monitoring, etc.) — full apply without targets
    # fills in anything else not covered by -target (safe no-op if already applied).
    if getattr(args, "full", False):
        print("\nApplying remaining stack modules...")
        if not terraform_apply(session_id, targets=None, label="full-remainder"):
            print("\nFull remainder apply failed.")
            sys.exit(1)

    persist_session_id(session_id)
    export_evidence("apply_after")
    print("\n✓ Deployment complete (foundation + AMI + instances)!")
    print(f"  Re-use this session: SESSION={session_id} or .hpc-session")


def cmd_down(args):
    """Handle 'down' command."""
    session_id = resolve_session_id(for_destroy=True)
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

    # Clear persisted session so the next up starts clean
    sf = _session_file()
    if sf.exists():
        sf.unlink()
        print(f"Removed {sf}")

    print("\n✓ Destruction complete!")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="HPC Platform Operations Test Bed Deployment Script"
    )

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    up_p = subparsers.add_parser(
        "up",
        help="Ordered deploy: foundation → ami-build → instances",
    )
    up_p.add_argument(
        "--skip-ami",
        action="store_true",
        help="Skip Image Builder run; require SSM current AMI already set",
    )
    up_p.add_argument(
        "--full",
        action="store_true",
        help="After instances, apply remaining modules (fsx, monitoring, ...)",
    )

    subparsers.add_parser(
        "foundation",
        help="Phase 1: VPC/subnets/SGs/EFS + Image Builder pipeline (no EC2)",
    )
    subparsers.add_parser(
        "instances",
        help="Phase 3: controller + login/debug (requires AMI in SSM)",
    )
    subparsers.add_parser("down", help="Destroy infrastructure")

    args = parser.parse_args()

    if args.command == "up":
        cmd_up(args)
    elif args.command == "foundation":
        cmd_foundation(args)
    elif args.command == "instances":
        cmd_instances(args)
    elif args.command == "down":
        cmd_down(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
