#!/usr/bin/env python3
"""
Slurm SuspendProgram — terminate EC2 instances for idle cloud nodes.

Invoked by slurmctld with node names on stdin or as arguments.
For each node:
  1. Find instance by NodeName tag
  2. Terminate it
  3. Remove private DNS A record
  4. Emit structured log event

Environment:
  HPC_HOSTED_ZONE_ID, HPC_HOSTED_ZONE_NAME, HPC_PROJECT, AWS_DEFAULT_REGION
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from datetime import datetime, timezone
from typing import List, Optional

import boto3
from botocore.exceptions import ClientError

LOG = logging.getLogger("slurm_suspend")


def _configure_logging() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stderr,
    )


def structured_event(event: str, **fields) -> None:
    payload = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "event": event,
        **fields,
    }
    print(json.dumps(payload, default=str), flush=True)
    LOG.info("%s %s", event, fields)


def find_instances_by_node(node_name: str) -> List[str]:
    ec2 = boto3.client("ec2")
    resp = ec2.describe_instances(
        Filters=[
            {"Name": "tag:NodeName", "Values": [node_name]},
            {"Name": "instance-state-name", "Values": ["pending", "running", "stopping", "stopped"]},
        ]
    )
    ids: List[str] = []
    for res in resp.get("Reservations", []):
        for inst in res.get("Instances", []):
            ids.append(inst["InstanceId"])
    return ids


def terminate_instances(instance_ids: List[str]) -> None:
    if not instance_ids:
        return
    ec2 = boto3.client("ec2")
    ec2.terminate_instances(InstanceIds=instance_ids)


def remove_dns(node_name: str, hosted_zone_id: str, hosted_zone_name: str) -> None:
    if not hosted_zone_id:
        return
    r53 = boto3.client("route53")
    fqdn = f"{node_name}.{hosted_zone_name.rstrip('.')}."
    # Need current record to delete
    try:
        resp = r53.list_resource_record_sets(
            HostedZoneId=hosted_zone_id,
            StartRecordName=fqdn,
            StartRecordType="A",
            MaxItems="1",
        )
    except ClientError as exc:
        LOG.warning("list_resource_record_sets failed: %s", exc)
        return

    sets = resp.get("ResourceRecordSets", [])
    if not sets or sets[0]["Name"].rstrip(".") != fqdn.rstrip("."):
        LOG.info("No DNS record for %s", fqdn)
        return

    try:
        r53.change_resource_record_sets(
            HostedZoneId=hosted_zone_id,
            ChangeBatch={
                "Changes": [
                    {
                        "Action": "DELETE",
                        "ResourceRecordSet": sets[0],
                    }
                ]
            },
        )
    except ClientError as exc:
        LOG.warning("DNS delete failed for %s: %s", fqdn, exc)


def suspend_node(node_name: str, dry_run: bool = False) -> bool:
    zone_id = os.environ.get("HPC_HOSTED_ZONE_ID", "")
    zone_name = os.environ.get("HPC_HOSTED_ZONE_NAME", "hpc.internal")

    structured_event("suspend_start", node=node_name, dry_run=dry_run)

    try:
        ids = find_instances_by_node(node_name)
    except ClientError as exc:
        structured_event("suspend_failed", node=node_name, reason=str(exc))
        return False

    if not ids:
        # Idempotent: nothing to do
        structured_event("suspend_noop", node=node_name, reason="no matching instances")
        remove_dns(node_name, zone_id, zone_name)
        return True

    if dry_run:
        structured_event("suspend_dry_run", node=node_name, instance_ids=ids)
        return True

    try:
        terminate_instances(ids)
    except ClientError as exc:
        structured_event("suspend_failed", node=node_name, reason=str(exc), instance_ids=ids)
        return False

    remove_dns(node_name, zone_id, zone_name)
    structured_event("suspend_success", node=node_name, instance_ids=ids)
    return True


def parse_nodes(argv: List[str]) -> List[str]:
    nodes: List[str] = []
    if argv:
        for a in argv:
            nodes.extend(x for x in a.replace(",", " ").split() if x)
    if not nodes and not sys.stdin.isatty():
        data = sys.stdin.read()
        nodes.extend(x for x in data.replace(",", " ").split() if x)
    return nodes


def main(argv: Optional[List[str]] = None) -> int:
    _configure_logging()
    parser = argparse.ArgumentParser(description="Slurm SuspendProgram")
    parser.add_argument("nodes", nargs="*", help="Node names to suspend")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    nodes = parse_nodes(args.nodes)
    if not nodes:
        structured_event("suspend_noop", reason="no nodes provided")
        return 0

    ok = True
    for node in nodes:
        if not suspend_node(node, dry_run=args.dry_run):
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
