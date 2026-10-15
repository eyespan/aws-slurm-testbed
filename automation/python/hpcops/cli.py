#!/usr/bin/env python3
"""
hpcops — operations CLI for the HPC testbed.

Subcommands:
  drain-node     Drain a node (scontrol update State=DRAIN)
  diagnose-job   Show job + node context for a job id
  diagnose-node  Show node state, reason, and recent events
  requeue-stuck  Requeue jobs stuck in CF/CG beyond a threshold

Dry-run by default; pass --yes for destructive actions.
JSON lines are appended to evidence/ops-log.jsonl.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional

EVIDENCE_LOG = Path(os.environ.get("HPC_OPS_LOG", "evidence/ops-log.jsonl"))


def log_action(action: str, **fields) -> None:
    EVIDENCE_LOG.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "action": action,
        **fields,
    }
    with EVIDENCE_LOG.open("a") as f:
        f.write(json.dumps(record, default=str) + "\n")
    print(json.dumps(record, default=str))


def run_cmd(cmd: List[str], check: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def drain_node(node: str, reason: str, yes: bool) -> int:
    cmd = ["scontrol", "update", f"NodeName={node}", "State=DRAIN", f"Reason={reason}"]
    if not yes:
        log_action("drain-node", node=node, reason=reason, dry_run=True, cmd=" ".join(cmd))
        print(f"[dry-run] would run: {' '.join(cmd)}")
        return 0
    result = run_cmd(cmd)
    log_action(
        "drain-node",
        node=node,
        reason=reason,
        dry_run=False,
        returncode=result.returncode,
        stdout=result.stdout.strip(),
        stderr=result.stderr.strip(),
    )
    return result.returncode


def diagnose_job(job_id: str) -> int:
    out = {}
    for label, cmd in [
        ("scontrol", ["scontrol", "show", "job", job_id, "-d"]),
        ("sacct", ["sacct", "-j", job_id, "--format=JobID,JobName,State,ExitCode,Elapsed,NodeList,Reason", "-P"]),
    ]:
        r = run_cmd(cmd)
        out[label] = {"returncode": r.returncode, "stdout": r.stdout, "stderr": r.stderr}
    log_action("diagnose-job", job_id=job_id, result=out)
    print(out.get("scontrol", {}).get("stdout", ""))
    print(out.get("sacct", {}).get("stdout", ""))
    return 0


def diagnose_node(node: str) -> int:
    r = run_cmd(["scontrol", "show", "node", node, "-d"])
    log_action(
        "diagnose-node",
        node=node,
        returncode=r.returncode,
        stdout=r.stdout,
        stderr=r.stderr,
    )
    print(r.stdout or r.stderr)
    return r.returncode


def requeue_stuck(minutes: int, yes: bool) -> int:
    """Find jobs in CF/CG longer than threshold and requeue them."""
    r = run_cmd(["squeue", "-h", "-o", "%i %T %M %r"])
    candidates = []
    for line in r.stdout.splitlines():
        parts = line.split(None, 3)
        if len(parts) < 3:
            continue
        jid, state, elapsed = parts[0], parts[1], parts[2]
        if state not in ("CF", "CONFIGURING", "CG", "COMPLETING"):
            continue
        # elapsed is D-HH:MM:SS or HH:MM:SS or MM:SS
        secs = _parse_elapsed(elapsed)
        if secs >= minutes * 60:
            candidates.append(jid)

    if not candidates:
        log_action("requeue-stuck", candidates=[], dry_run=not yes)
        print("No stuck jobs found")
        return 0

    if not yes:
        log_action("requeue-stuck", candidates=candidates, dry_run=True)
        print(f"[dry-run] would requeue: {candidates}")
        return 0

    results = []
    for jid in candidates:
        rr = run_cmd(["scontrol", "requeue", jid])
        results.append({"job_id": jid, "returncode": rr.returncode, "stderr": rr.stderr.strip()})
    log_action("requeue-stuck", candidates=candidates, dry_run=False, results=results)
    return 0 if all(x["returncode"] == 0 for x in results) else 1


def _parse_elapsed(s: str) -> int:
    s = s.strip()
    days = 0
    if "-" in s:
        d, s = s.split("-", 1)
        days = int(d)
    parts = [int(x) for x in s.split(":")]
    if len(parts) == 3:
        h, m, sec = parts
    elif len(parts) == 2:
        h, m, sec = 0, parts[0], parts[1]
    else:
        h, m, sec = 0, 0, parts[0]
    return days * 86400 + h * 3600 + m * 60 + sec


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="hpcops", description="HPC operations CLI")
    p.add_argument("--yes", action="store_true", help="Execute destructive actions (default is dry-run)")
    sub = p.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("drain-node", help="Drain a Slurm node")
    d.add_argument("node")
    d.add_argument("--reason", default="ops drain")

    j = sub.add_parser("diagnose-job", help="Diagnose a job")
    j.add_argument("job_id")

    n = sub.add_parser("diagnose-node", help="Diagnose a node")
    n.add_argument("node")

    r = sub.add_parser("requeue-stuck", help="Requeue stuck CF/CG jobs")
    r.add_argument("--minutes", type=int, default=30, help="Stuck threshold in minutes")

    return p


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.cmd == "drain-node":
        return drain_node(args.node, args.reason, args.yes)
    if args.cmd == "diagnose-job":
        return diagnose_job(args.job_id)
    if args.cmd == "diagnose-node":
        return diagnose_node(args.node)
    if args.cmd == "requeue-stuck":
        return requeue_stuck(args.minutes, args.yes)
    parser.error(f"unknown command {args.cmd}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
