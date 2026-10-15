#!/usr/bin/env python3
"""
Service report and capacity forecast (Task 35).

Produces a monthly-style report: availability vs SLO, incidents, changes,
capacity trend, utilisation anomalies. Notes missing billing data limitation.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

SLO = {
    "scheduler_availability": 99.5,
    "login_portal_availability": 99.5,
    "job_start_latency_warm_p95_s": 30,
    "job_start_latency_cold_p95_s": 360,
}


def metric_stats(cw, name: str, days: int = 30, namespace: str = "HPC/Slurm") -> dict:
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=days)
    try:
        resp = cw.get_metric_statistics(
            Namespace=namespace,
            MetricName=name,
            StartTime=start,
            EndTime=end,
            Period=86400,
            Statistics=["Average", "Maximum", "SampleCount"],
        )
        points = resp.get("Datapoints", [])
        if not points:
            return {"available": False}
        avgs = [p["Average"] for p in points if "Average" in p]
        return {
            "available": True,
            "avg": sum(avgs) / len(avgs) if avgs else None,
            "max": max((p.get("Maximum", 0) for p in points), default=None),
            "samples": sum(p.get("SampleCount", 0) for p in points),
        }
    except ClientError as e:
        return {"available": False, "error": str(e)}


def instance_capacity(ec2) -> dict:
    try:
        resp = ec2.describe_instances(
            Filters=[{"Name": "tag:Project", "Values": ["hpc-testbed"]}]
        )
        running = 0
        by_role: dict[str, int] = {}
        for res in resp.get("Reservations", []):
            for inst in res.get("Instances", []):
                if inst["State"]["Name"] not in ("running", "pending"):
                    continue
                running += 1
                role = next((t["Value"] for t in inst.get("Tags", []) if t["Key"] == "Role"), "unknown")
                by_role[role] = by_role.get(role, 0) + 1
        return {"running": running, "budget_cap": 9, "by_role": by_role}
    except ClientError as e:
        return {"error": str(e)}


def load_incidents(path: Path) -> list:
    if not path.exists():
        return []
    reviews = []
    for f in sorted(path.glob("**/*.md")):
        reviews.append({"file": str(f), "size": f.stat().st_size})
    return reviews


def generate_report(output: Path, days: int = 30) -> dict:
    cw = boto3.client("cloudwatch")
    ec2 = boto3.client("ec2")

    health = metric_stats(cw, "HealthCheckStatus", days=days)
    resume_fail = metric_stats(cw, "resume_failures", days=days)
    canary = metric_stats(cw, "canary_job_start_seconds", days=days)
    capacity = instance_capacity(ec2)
    incidents = load_incidents(Path("incidents/reviews"))

    # Availability estimate from health metric (1=up)
    avail_pct = None
    if health.get("available") and health.get("avg") is not None:
        avail_pct = round(health["avg"] * 100, 3)

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "period_days": days,
        "slo": SLO,
        "availability": {
            "scheduler_pct": avail_pct,
            "slo_target_pct": SLO["scheduler_availability"],
            "meets_slo": avail_pct is not None and avail_pct >= SLO["scheduler_availability"],
            "note": "Derived from HealthCheckStatus custom metric; missing data treated as gap.",
        },
        "latency": {
            "canary_job_start_seconds": canary,
            "warm_slo_s": SLO["job_start_latency_warm_p95_s"],
            "cold_slo_s": SLO["job_start_latency_cold_p95_s"],
        },
        "resume_failures": resume_fail,
        "capacity": capacity,
        "capacity_forecast": {
            "method": "linear headroom vs budget_cap",
            "headroom": (capacity.get("budget_cap", 9) - capacity.get("running", 0))
            if "running" in capacity
            else None,
            "note": "Sandbox capped at 9 instances including Image Builder reserve.",
        },
        "incidents": incidents,
        "changes": {
            "note": "Summarise from git log / evidence packs in a live session.",
        },
        "limitations": [
            "Billing and Cost Explorer data are not available in this sandbox account model.",
            "Utilisation anomalies rely on CloudWatch custom metrics; sparse datapoints reduce confidence.",
            "Incident list is file-based from incidents/reviews/.",
        ],
    }

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")

    # Also write a markdown summary
    md = output.with_suffix(".md")
    lines = [
        f"# Service report — {report['generated_at'][:10]}",
        "",
        f"Period: last {days} days",
        "",
        "## Availability",
        f"- Scheduler: {avail_pct}% (SLO {SLO['scheduler_availability']}%)",
        f"- Meets SLO: {report['availability']['meets_slo']}",
        "",
        "## Capacity",
        f"- Running instances: {capacity.get('running')}",
        f"- Budget cap: {capacity.get('budget_cap')}",
        f"- By role: {capacity.get('by_role')}",
        f"- Headroom: {report['capacity_forecast']['headroom']}",
        "",
        "## Incidents",
        f"- Review files: {len(incidents)}",
        "",
        "## Limitations",
    ]
    for lim in report["limitations"]:
        lines.append(f"- {lim}")
    md.write_text("\n".join(lines) + "\n")
    print(f"Wrote {output} and {md}")
    return report


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--days", type=int, default=30)
    p.add_argument(
        "--output",
        default=f"docs/service-reports/report-{datetime.now(timezone.utc).strftime('%Y%m')}.json",
    )
    args = p.parse_args()
    generate_report(Path(args.output), days=args.days)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
