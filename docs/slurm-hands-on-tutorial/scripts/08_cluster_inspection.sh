#!/usr/bin/env bash
set -u
echo "== Partition summary =="
sinfo 2>&1 || true
echo
echo "== Node-oriented view =="
sinfo --Node 2>&1 || true
echo
echo "== Longer summary =="
sinfo --long 2>&1 || true
echo
echo "== Partition details (read-only) =="
scontrol show partition 2>&1 || true
echo
echo "== Node details (read-only; output may be long) =="
scontrol show nodes 2>&1 | head -n 80 || true
echo
echo "This script deliberately does not run any state-changing scontrol commands."
