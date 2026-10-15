#!/usr/bin/env python3
"""
AMI promotion script (Task 24).

After a candidate AMI passes smoke tests, write SSM parameters:
  /hpc-testbed/ami/compute/current
  /hpc-testbed/ami/compute/previous

Rollback: make ami-rollback swaps current <-> previous.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

SSM_CURRENT = "/hpc-testbed/ami/compute/current"
SSM_PREVIOUS = "/hpc-testbed/ami/compute/previous"
SSM_CANDIDATE = "/hpc-testbed/ami/compute/candidate"


def get_param(ssm, name: str) -> str | None:
    try:
        return ssm.get_parameter(Name=name)["Parameter"]["Value"]
    except ClientError:
        return None


def put_param(ssm, name: str, value: str) -> None:
    ssm.put_parameter(Name=name, Value=value, Type="String", Overwrite=True)


def promote(candidate_ami: str, skip_smoke: bool = False) -> int:
    ssm = boto3.client("ssm")
    ec2 = boto3.client("ec2")

    # Validate AMI exists
    try:
        images = ec2.describe_images(ImageIds=[candidate_ami])["Images"]
        if not images:
            print(f"AMI not found: {candidate_ami}", file=sys.stderr)
            return 1
    except ClientError as e:
        print(f"describe_images failed: {e}", file=sys.stderr)
        return 1

    if not skip_smoke:
        print("Smoke test placeholder: ensure tests/scheduler/test_smoke.sh passed against candidate")
        # Live smoke is SANDBOX; here we only gate on AMI state
        if images[0].get("State") != "available":
            print(f"AMI state is {images[0].get('State')}, expected available", file=sys.stderr)
            return 1

    current = get_param(ssm, SSM_CURRENT)
    if current:
        put_param(ssm, SSM_PREVIOUS, current)
        print(f"previous <- {current}")
    put_param(ssm, SSM_CURRENT, candidate_ami)
    put_param(ssm, SSM_CANDIDATE, candidate_ami)
    print(json.dumps({
        "event": "ami_promoted",
        "ts": datetime.now(timezone.utc).isoformat(),
        "current": candidate_ami,
        "previous": current,
    }))
    return 0


def rollback() -> int:
    ssm = boto3.client("ssm")
    current = get_param(ssm, SSM_CURRENT)
    previous = get_param(ssm, SSM_PREVIOUS)
    if not previous:
        print("No previous AMI to roll back to", file=sys.stderr)
        return 1
    put_param(ssm, SSM_CURRENT, previous)
    if current:
        put_param(ssm, SSM_PREVIOUS, current)
    print(json.dumps({
        "event": "ami_rollback",
        "ts": datetime.now(timezone.utc).isoformat(),
        "current": previous,
        "previous": current,
    }))
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Promote or roll back compute AMI")
    sub = p.add_subparsers(dest="cmd", required=True)
    prom = sub.add_parser("promote")
    prom.add_argument("--ami", required=True, help="Candidate AMI ID")
    prom.add_argument("--skip-smoke", action="store_true")
    sub.add_parser("rollback")
    args = p.parse_args()
    if args.cmd == "promote":
        return promote(args.ami, skip_smoke=args.skip_smoke)
    return rollback()


if __name__ == "__main__":
    raise SystemExit(main())
