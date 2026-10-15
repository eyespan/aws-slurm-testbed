"""
inspector-ticket Lambda (Task 24).

Turns Inspector findings above a severity threshold into a markdown ticket
stored in S3 with a remediation due date.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone

import boto3

SEVERITY_RANK = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1, "INFORMATIONAL": 0}
THRESHOLD = os.environ.get("SEVERITY_THRESHOLD", "HIGH")
BUCKET = os.environ.get("TICKET_BUCKET", "")
DUE_DAYS = int(os.environ.get("REMEDIATION_DUE_DAYS", "14"))


def handler(event, context):
    inspector = boto3.client("inspector2")
    s3 = boto3.client("s3")
    min_rank = SEVERITY_RANK.get(THRESHOLD, 3)

    findings = []
    paginator = inspector.get_paginator("list_findings")
    for page in paginator.paginate(
        filterCriteria={
            "findingStatus": [{"comparison": "EQUALS", "value": "ACTIVE"}],
        }
    ):
        for f in page.get("findings", []):
            sev = (f.get("severity") or "INFORMATIONAL").upper()
            if SEVERITY_RANK.get(sev, 0) >= min_rank:
                findings.append(f)

    due = (datetime.now(timezone.utc) + timedelta(days=DUE_DAYS)).date().isoformat()
    lines = [
        f"# Inspector findings ticket",
        f"",
        f"- Generated: {datetime.now(timezone.utc).isoformat()}",
        f"- Threshold: {THRESHOLD}",
        f"- Remediation due: {due}",
        f"- Finding count: {len(findings)}",
        "",
        "## Findings",
        "",
    ]
    for f in findings[:50]:
        lines.append(
            f"- **{f.get('severity')}** `{f.get('findingArn', '')[-40:]}` "
            f"{f.get('title', 'untitled')} — {f.get('description', '')[:120]}"
        )
    body = "\n".join(lines) + "\n"
    key = f"inspector-tickets/{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.md"
    if BUCKET:
        s3.put_object(Bucket=BUCKET, Key=key, Body=body.encode(), ContentType="text/markdown")
    return {"statusCode": 200, "count": len(findings), "s3_key": key if BUCKET else None, "body_preview": body[:500]}
