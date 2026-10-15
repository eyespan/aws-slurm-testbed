#!/usr/bin/env python3
"""
Slurm ResumeProgram — launch EC2 instances for cloud nodes.

Invoked by slurmctld with node names on stdin or as arguments.
For each node:
  1. Resolve launch template + AMI from SSM
  2. RunInstances (tagged, in private subnet)
  3. Register A record in the private hosted zone
  4. Emit structured log + resume_latency_seconds metric
On failure: scontrol update State=DOWN Reason=... and emit failure metric.

Environment (set by controller user-data / systemd):
  HPC_LAUNCH_TEMPLATE_ID, HPC_SUBNET_ID, HPC_SECURITY_GROUP_IDS,
  HPC_HOSTED_ZONE_ID, HPC_HOSTED_ZONE_NAME, HPC_PROJECT, HPC_ENV,
  HPC_SESSION, HPC_INSTANCE_TYPE, AWS_DEFAULT_REGION
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Iterable, List, Optional

import boto3
from botocore.exceptions import ClientError

LOG = logging.getLogger("slurm_resume")
METRIC_NAMESPACE = "HPC/Slurm"


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


def scontrol_down(node: str, reason: str) -> None:
    cmd = [
        "scontrol",
        "update",
        f"NodeName={node}",
        "State=DOWN",
        f"Reason={reason[:100]}",
    ]
    try:
        subprocess.run(cmd, check=False, capture_output=True, text=True, timeout=30)
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        LOG.warning("scontrol failed for %s: %s", node, exc)


def put_metric(name: str, value: float, unit: str = "Seconds", dimensions: Optional[dict] = None) -> None:
    try:
        cw = boto3.client("cloudwatch")
        dims = [{"Name": k, "Value": str(v)} for k, v in (dimensions or {}).items()]
        cw.put_metric_data(
            Namespace=METRIC_NAMESPACE,
            MetricData=[
                {
                    "MetricName": name,
                    "Value": value,
                    "Unit": unit,
                    "Dimensions": dims,
                    "Timestamp": datetime.now(timezone.utc),
                }
            ],
        )
    except ClientError as exc:
        LOG.warning("put_metric_data failed: %s", exc)


def resolve_ami(ssm_path: str = "/hpc-testbed/ami/compute/current") -> Optional[str]:
    try:
        ssm = boto3.client("ssm")
        return ssm.get_parameter(Name=ssm_path)["Parameter"]["Value"]
    except ClientError as exc:
        LOG.error("AMI SSM lookup failed: %s", exc)
        return None


def launch_instance(
    node_name: str,
    *,
    launch_template_id: str,
    subnet_id: str,
    security_group_ids: List[str],
    instance_type: str,
    project: str,
    env: str,
    session: str,
    ami_id: Optional[str] = None,
) -> str:
    """Launch one instance; return instance_id."""
    ec2 = boto3.client("ec2")
    tags = [
        {"Key": "Name", "Value": f"{project}-{env}-{session}-{node_name}"},
        {"Key": "Project", "Value": project},
        {"Key": "Env", "Value": env},
        {"Key": "Session", "Value": session},
        {"Key": "Role", "Value": "compute"},
        {"Key": "NodeName", "Value": node_name},
        {"Key": "ManagedBy", "Value": "slurm-resume"},
    ]
    lt = {"LaunchTemplateId": launch_template_id, "Version": "$Latest"}
    kwargs = {
        "LaunchTemplate": lt,
        "MinCount": 1,
        "MaxCount": 1,
        "SubnetId": subnet_id,
        "SecurityGroupIds": security_group_ids,
        "TagSpecifications": [
            {"ResourceType": "instance", "Tags": tags},
            {"ResourceType": "volume", "Tags": tags},
        ],
    }
    if instance_type:
        kwargs["InstanceType"] = instance_type
    if ami_id:
        # Override AMI from launch template when SSM current is set
        kwargs["ImageId"] = ami_id

    resp = ec2.run_instances(**kwargs)
    instance_id = resp["Instances"][0]["InstanceId"]
    return instance_id


def register_dns(
    node_name: str,
    private_ip: str,
    hosted_zone_id: str,
    hosted_zone_name: str,
) -> None:
    r53 = boto3.client("route53")
    fqdn = f"{node_name}.{hosted_zone_name.rstrip('.')}."
    r53.change_resource_record_sets(
        HostedZoneId=hosted_zone_id,
        ChangeBatch={
            "Changes": [
                {
                    "Action": "UPSERT",
                    "ResourceRecordSet": {
                        "Name": fqdn,
                        "Type": "A",
                        "TTL": 60,
                        "ResourceRecords": [{"Value": private_ip}],
                    },
                }
            ]
        },
    )


def wait_for_ip(instance_id: str, timeout: int = 120) -> Optional[str]:
    ec2 = boto3.client("ec2")
    deadline = time.time() + timeout
    while time.time() < deadline:
        resp = ec2.describe_instances(InstanceIds=[instance_id])
        inst = resp["Reservations"][0]["Instances"][0]
        ip = inst.get("PrivateIpAddress")
        state = inst["State"]["Name"]
        if ip and state in ("pending", "running"):
            return ip
        if state in ("terminated", "shutting-down"):
            return None
        time.sleep(3)
    return None


def resume_node(node_name: str, dry_run: bool = False) -> bool:
    start = time.monotonic()
    project = os.environ.get("HPC_PROJECT", "hpc-testbed")
    env = os.environ.get("HPC_ENV", "dev")
    session = os.environ.get("HPC_SESSION", "default")
    lt_id = os.environ.get("HPC_LAUNCH_TEMPLATE_ID", "")
    subnet_id = os.environ.get("HPC_SUBNET_ID", "")
    sg_ids = [s for s in os.environ.get("HPC_SECURITY_GROUP_IDS", "").split(",") if s]
    zone_id = os.environ.get("HPC_HOSTED_ZONE_ID", "")
    zone_name = os.environ.get("HPC_HOSTED_ZONE_NAME", "hpc.internal")
    instance_type = os.environ.get("HPC_INSTANCE_TYPE", "t3.micro")

    structured_event("resume_start", node=node_name, dry_run=dry_run)

    if not lt_id or not subnet_id:
        reason = "missing HPC_LAUNCH_TEMPLATE_ID or HPC_SUBNET_ID"
        structured_event("resume_failed", node=node_name, reason=reason)
        scontrol_down(node_name, reason)
        put_metric("resume_failures", 1, unit="Count", dimensions={"NodeName": node_name})
        return False

    if dry_run:
        structured_event("resume_dry_run", node=node_name)
        return True

    ami_id = resolve_ami()
    try:
        instance_id = launch_instance(
            node_name,
            launch_template_id=lt_id,
            subnet_id=subnet_id,
            security_group_ids=sg_ids,
            instance_type=instance_type,
            project=project,
            env=env,
            session=session,
            ami_id=ami_id,
        )
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "Unknown")
        reason = f"EC2 launch failed: {code}"
        structured_event("resume_failed", node=node_name, reason=reason, error=str(exc))
        scontrol_down(node_name, reason)
        put_metric("resume_failures", 1, unit="Count", dimensions={"NodeName": node_name, "ErrorCode": code})
        return False

    private_ip = wait_for_ip(instance_id)
    if not private_ip:
        reason = "instance has no private IP / terminated early"
        structured_event("resume_failed", node=node_name, instance_id=instance_id, reason=reason)
        scontrol_down(node_name, reason)
        put_metric("resume_failures", 1, unit="Count", dimensions={"NodeName": node_name})
        return False

    if zone_id:
        try:
            register_dns(node_name, private_ip, zone_id, zone_name)
        except ClientError as exc:
            LOG.warning("DNS registration failed for %s: %s", node_name, exc)

    latency = time.monotonic() - start
    put_metric("resume_latency_seconds", latency, dimensions={"NodeName": node_name})
    structured_event(
        "resume_success",
        node=node_name,
        instance_id=instance_id,
        private_ip=private_ip,
        resume_latency_seconds=round(latency, 3),
    )
    return True


def parse_nodes(argv: List[str]) -> List[str]:
    """Slurm may pass nodes as args or on stdin (space/comma separated)."""
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
    parser = argparse.ArgumentParser(description="Slurm ResumeProgram")
    parser.add_argument("nodes", nargs="*", help="Node names to resume")
    parser.add_argument("--dry-run", action="store_true", help="Log only, do not launch")
    args = parser.parse_args(argv)

    nodes = parse_nodes(args.nodes)
    if not nodes:
        structured_event("resume_noop", reason="no nodes provided")
        return 0

    ok = True
    for node in nodes:
        if not resume_node(node, dry_run=args.dry_run):
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
