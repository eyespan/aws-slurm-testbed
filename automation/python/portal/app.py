#!/usr/bin/env python3
"""
Read-only HPC status portal (Task 22).
Serves /healthz and a simple HTML/JSON view of sinfo + recent canaries.
Intended to run on the login node behind an ALB.
"""

from __future__ import annotations

import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

try:
    from flask import Flask, jsonify, Response
except ImportError:  # pragma: no cover
    from http.server import BaseHTTPRequestHandler, HTTPServer

    Flask = None  # type: ignore

CANARY_DIR = Path(os.environ.get("CANARY_DIR", "/shared/canary"))
APP_VERSION = "0.1.0"


def run(cmd: list[str]) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        return r.stdout if r.returncode == 0 else r.stderr
    except Exception as e:
        return f"error: {e}"


def collect_status() -> dict:
    return {
        "ts": datetime.now(timezone.utc).isoformat(),
        "version": APP_VERSION,
        "sinfo": run(["sinfo", "-N", "-l"]),
        "squeue": run(["squeue", "-l"]),
        "canaries": _recent_canaries(),
    }


def _recent_canaries(limit: int = 10) -> list[dict]:
    if not CANARY_DIR.exists():
        return []
    files = sorted(CANARY_DIR.glob("*.out"), key=lambda p: p.stat().st_mtime, reverse=True)
    out = []
    for f in files[:limit]:
        out.append({
            "file": f.name,
            "mtime": datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc).isoformat(),
            "snippet": f.read_text(errors="replace")[:200],
        })
    return out


if Flask is not None:
    app = Flask(__name__)

    @app.get("/healthz")
    def healthz():
        return jsonify({"status": "ok", "version": APP_VERSION})

    @app.get("/")
    def index():
        data = collect_status()
        html = f"""<!DOCTYPE html>
<html><head><title>HPC Status</title>
<style>body{{font-family:system-ui;margin:2rem}} pre{{background:#111;color:#eee;padding:1rem;overflow:auto}}</style>
</head><body>
<h1>HPC Platform Status</h1>
<p>Updated {data['ts']}</p>
<h2>sinfo</h2><pre>{data['sinfo']}</pre>
<h2>squeue</h2><pre>{data['squeue']}</pre>
<h2>Recent canaries</h2><pre>{json.dumps(data['canaries'], indent=2)}</pre>
</body></html>"""
        return Response(html, mimetype="text/html")

    @app.get("/api/status")
    def api_status():
        return jsonify(collect_status())

    def main():
        port = int(os.environ.get("PORT", "8080"))
        app.run(host="0.0.0.0", port=port)

else:
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            if self.path.startswith("/healthz"):
                body = json.dumps({"status": "ok", "version": APP_VERSION}).encode()
            else:
                body = json.dumps(collect_status(), indent=2).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass

    def main():
        port = int(os.environ.get("PORT", "8080"))
        HTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
