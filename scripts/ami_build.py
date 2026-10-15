#!/usr/bin/env python3
"""
Start the HPC Image Builder pipeline, wait for completion, and promote the AMI.

The Terraform pipeline resource only schedules weekly runs (Sunday 02:00 UTC).
It does not execute on `terraform apply`. Use this script (or `make ami-build`)
before launching controller/login/debug so instances boot from an AMI that
already contains Slurm + munge under /opt/slurm.

Usage:
  python3 scripts/ami_build.py
  python3 scripts/ami_build.py --timeout-minutes 120
  python3 scripts/ami_build.py --pipeline-arn arn:aws:imagebuilder:...
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# Reuse promote helper
sys.path.insert(0, str(Path(__file__).resolve().parent))
from image_promote import promote  # noqa: E402

SSM_CURRENT = "/hpc-testbed/ami/compute/current"


def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def resolve_pipeline_arn(explicit: str | None) -> str:
    if explicit:
        return explicit
    # Prefer terraform output from root module
    tf = Path("terraform")
    if (tf / "terraform.tfstate").exists() or (tf / ".terraform").exists():
        r = _run(
            [
                "terraform",
                f"-chdir={tf}",
                "output",
                "-raw",
                "image_pipeline_arn",
            ]
        )
        if r.returncode == 0 and r.stdout.strip().startswith("arn:"):
            return r.stdout.strip()
    # Fallback: list pipelines tagged/named for this project
    r = _run(
        [
            "aws",
            "imagebuilder",
            "list-image-pipelines",
            "--query",
            "imagePipelineList[?contains(name, `hpc-compute`)].arn | [0]",
            "--output",
            "text",
        ]
    )
    if r.returncode == 0 and r.stdout.strip() and r.stdout.strip() != "None":
        return r.stdout.strip()
    raise SystemExit(
        "Could not resolve image pipeline ARN.\n"
        "  1) From repo root run:  make foundation   # creates VPC + Image Builder pipeline\n"
        "  2) Then:               make ami-build\n"
        "  Or pass:               python3 scripts/ami_build.py --pipeline-arn arn:aws:imagebuilder:..."
    )


def start_execution(pipeline_arn: str) -> str:
    r = _run(
        [
            "aws",
            "imagebuilder",
            "start-image-pipeline-execution",
            "--image-pipeline-arn",
            pipeline_arn,
            "--output",
            "json",
        ]
    )
    if r.returncode != 0:
        print(r.stderr or r.stdout, file=sys.stderr)
        raise SystemExit(f"start-image-pipeline-execution failed: {r.returncode}")
    data = json.loads(r.stdout)
    image_build_version_arn = data.get("imageBuildVersionArn") or data.get(
        "imageBuildVersionArn".lower(), ""
    )
    # API returns imageBuildVersionArn
    if not image_build_version_arn:
        # Some CLI versions nest differently
        image_build_version_arn = data.get("imageBuildVersionArn", "")
    if not image_build_version_arn:
        print(json.dumps(data, indent=2))
        raise SystemExit("No imageBuildVersionArn in start response")
    print(f"Started build: {image_build_version_arn}")
    return image_build_version_arn


def wait_for_image(image_build_version_arn: str, timeout_minutes: int) -> dict:
    deadline = time.time() + timeout_minutes * 60
    last_status = ""
    while time.time() < deadline:
        r = _run(
            [
                "aws",
                "imagebuilder",
                "get-image",
                "--image-build-version-arn",
                image_build_version_arn,
                "--output",
                "json",
            ]
        )
        if r.returncode != 0:
            print(r.stderr or r.stdout, file=sys.stderr)
            time.sleep(30)
            continue
        data = json.loads(r.stdout)
        image = data.get("image") or data
        state = (image.get("state") or {}).get("status") or image.get("status") or ""
        if state != last_status:
            print(f"[{datetime.now(timezone.utc).isoformat()}] status={state}")
            last_status = state
        if state == "AVAILABLE":
            return image
        if state in ("FAILED", "CANCELLED", "DELETED"):
            reason = (image.get("state") or {}).get("reason") or ""
            raise SystemExit(f"Image build {state}: {reason}")
        time.sleep(45)
    raise SystemExit(f"Timed out after {timeout_minutes} minutes waiting for AMI")


def extract_ami_id(image: dict) -> str:
    # outputResources.amis[].image
    out = image.get("outputResources") or {}
    amis = out.get("amis") or []
    if not amis:
        raise SystemExit(f"No AMIs in outputResources: {json.dumps(out)[:500]}")
    ami_id = amis[0].get("image") or amis[0].get("amiId")
    if not ami_id:
        raise SystemExit(f"Could not parse AMI id from {amis[0]}")
    return ami_id


def main() -> int:
    parser = argparse.ArgumentParser(description="Build and promote HPC compute AMI")
    parser.add_argument("--pipeline-arn", default=None)
    parser.add_argument("--timeout-minutes", type=int, default=120)
    parser.add_argument(
        "--skip-promote",
        action="store_true",
        help="Do not write SSM /hpc-testbed/ami/compute/current",
    )
    args = parser.parse_args()

    pipeline_arn = resolve_pipeline_arn(args.pipeline_arn)
    print(f"Pipeline: {pipeline_arn}")

    build_arn = start_execution(pipeline_arn)
    image = wait_for_image(build_arn, args.timeout_minutes)
    ami_id = extract_ami_id(image)
    print(f"AMI available: {ami_id}")

    if args.skip_promote:
        print("Skipping SSM promote (--skip-promote)")
        print(json.dumps({"ami_id": ami_id, "image_build_version_arn": build_arn}))
        return 0

    rc = promote(ami_id, skip_smoke=True)
    if rc != 0:
        return rc
    print(
        f"Promoted {ami_id} → {SSM_CURRENT}. "
        "Re-apply or replace EC2 instances so they pick up the new AMI "
        "(terraform lifecycle currently ignores ami changes — taint/replace "
        "controller, login, and debug, or remove ignore_changes temporarily)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
