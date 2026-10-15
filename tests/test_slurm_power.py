"""Unit tests for slurm_resume.py and slurm_suspend.py using moto."""

from __future__ import annotations

import importlib.util
import json
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import boto3
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "automation" / "python"))

# Optional moto — skip if not installed
moto = pytest.importorskip("moto")
from moto import mock_aws  # noqa: E402


def _load(name: str, filename: str):
    path = ROOT / "automation" / "python" / filename
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


resume = _load("slurm_resume", "slurm_resume.py")
suspend = _load("slurm_suspend", "slurm_suspend.py")


@pytest.fixture
def aws_env(monkeypatch):
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SECURITY_TOKEN", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("HPC_PROJECT", "hpc-testbed")
    monkeypatch.setenv("HPC_ENV", "dev")
    monkeypatch.setenv("HPC_SESSION", "test")
    monkeypatch.setenv("HPC_INSTANCE_TYPE", "t3.micro")
    monkeypatch.setenv("HPC_HOSTED_ZONE_NAME", "hpc.internal")


def _setup_vpc_and_lt():
    ec2 = boto3.client("ec2", region_name="us-east-1")
    vpc = ec2.create_vpc(CidrBlock="10.0.0.0/16")["Vpc"]["VpcId"]
    subnet = ec2.create_subnet(VpcId=vpc, CidrBlock="10.0.1.0/24")["Subnet"]["SubnetId"]
    sg = ec2.create_security_group(GroupName="compute", Description="c", VpcId=vpc)["GroupId"]
    # Dummy AMI
    images = ec2.describe_images(Owners=["amazon"])["Images"]
    ami = images[0]["ImageId"] if images else "ami-12345678"
    lt = ec2.create_launch_template(
        LaunchTemplateName="hpc-compute",
        LaunchTemplateData={
            "ImageId": ami,
            "InstanceType": "t3.micro",
        },
    )["LaunchTemplate"]["LaunchTemplateId"]
    return subnet, sg, lt, ami


@mock_aws
def test_resume_success(aws_env, monkeypatch, capsys):
    subnet, sg, lt, ami = _setup_vpc_and_lt()
    ssm = boto3.client("ssm", region_name="us-east-1")
    ssm.put_parameter(Name="/hpc-testbed/ami/compute/current", Value=ami, Type="String")

    r53 = boto3.client("route53", region_name="us-east-1")
    zone = r53.create_hosted_zone(
        Name="hpc.internal",
        CallerReference="test-1",
        HostedZoneConfig={"PrivateZone": True},
        VPC={"VPCRegion": "us-east-1", "VPCId": "vpc-123"},
    )
    zone_id = zone["HostedZone"]["Id"].split("/")[-1]

    monkeypatch.setenv("HPC_LAUNCH_TEMPLATE_ID", lt)
    monkeypatch.setenv("HPC_SUBNET_ID", subnet)
    monkeypatch.setenv("HPC_SECURITY_GROUP_IDS", sg)
    monkeypatch.setenv("HPC_HOSTED_ZONE_ID", zone_id)

    with patch.object(resume, "scontrol_down") as sc:
        ok = resume.resume_node("std-1")
        sc.assert_not_called()

    assert ok is True
    out = capsys.readouterr().out
    events = [json.loads(line) for line in out.strip().splitlines() if line.startswith("{")]
    names = [e["event"] for e in events]
    assert "resume_start" in names
    assert "resume_success" in names
    success = next(e for e in events if e["event"] == "resume_success")
    assert success["node"] == "std-1"
    assert "instance_id" in success
    assert "resume_latency_seconds" in success


@mock_aws
def test_resume_capacity_failure(aws_env, monkeypatch, capsys):
    monkeypatch.setenv("HPC_LAUNCH_TEMPLATE_ID", "lt-missing")
    monkeypatch.setenv("HPC_SUBNET_ID", "subnet-missing")
    monkeypatch.setenv("HPC_SECURITY_GROUP_IDS", "sg-missing")

    with patch.object(resume, "scontrol_down") as sc:
        with patch.object(resume, "launch_instance", side_effect=resume.ClientError(
            {"Error": {"Code": "InsufficientInstanceCapacity", "Message": "no capacity"}},
            "RunInstances",
        )):
            # Also need resolve_ami to not fail hard - mock it
            with patch.object(resume, "resolve_ami", return_value="ami-abc"):
                ok = resume.resume_node("std-2")

        sc.assert_called()
        reason = sc.call_args[0][1]
        assert "InsufficientInstanceCapacity" in reason or "EC2 launch failed" in reason

    assert ok is False
    out = capsys.readouterr().out
    assert "resume_failed" in out


@mock_aws
def test_resume_idempotent_dry_run(aws_env, monkeypatch, capsys):
    monkeypatch.setenv("HPC_LAUNCH_TEMPLATE_ID", "lt-x")
    monkeypatch.setenv("HPC_SUBNET_ID", "subnet-x")
    ok = resume.resume_node("std-1", dry_run=True)
    assert ok is True
    assert "resume_dry_run" in capsys.readouterr().out


@mock_aws
def test_suspend_success(aws_env, monkeypatch, capsys):
    subnet, sg, lt, ami = _setup_vpc_and_lt()
    ec2 = boto3.client("ec2", region_name="us-east-1")
    inst = ec2.run_instances(
        ImageId=ami,
        InstanceType="t3.micro",
        MinCount=1,
        MaxCount=1,
        SubnetId=subnet,
        SecurityGroupIds=[sg],
        TagSpecifications=[
            {
                "ResourceType": "instance",
                "Tags": [
                    {"Key": "NodeName", "Value": "std-1"},
                    {"Key": "Role", "Value": "compute"},
                ],
            }
        ],
    )
    iid = inst["Instances"][0]["InstanceId"]

    with patch.object(suspend, "remove_dns"):
        ok = suspend.suspend_node("std-1")
    assert ok is True
    out = capsys.readouterr().out
    assert "suspend_success" in out
    state = ec2.describe_instances(InstanceIds=[iid])["Reservations"][0]["Instances"][0]["State"]["Name"]
    assert state in ("terminated", "shutting-down")


@mock_aws
def test_suspend_idempotent_no_instance(aws_env, monkeypatch, capsys):
    with patch.object(suspend, "remove_dns"):
        ok = suspend.suspend_node("std-99")
    assert ok is True
    assert "suspend_noop" in capsys.readouterr().out


def test_parse_nodes_args():
    assert resume.parse_nodes(["std-1,std-2", "std-3"]) == ["std-1", "std-2", "std-3"]
    assert suspend.parse_nodes(["std-1 std-2"]) == ["std-1", "std-2"]
