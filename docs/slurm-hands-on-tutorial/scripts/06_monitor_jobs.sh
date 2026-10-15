#!/usr/bin/env bash
set -eu
echo "== Your jobs =="
squeue --user="$USER" || true
echo
echo "== Running and pending jobs =="
squeue --states=RUNNING,PENDING --user="$USER" || true
echo
echo "== Common job commands (replace JOB_ID) =="
echo 'squeue -j JOB_ID'
echo 'scontrol show job JOB_ID'
echo 'scancel JOB_ID   # cancels the specified job; double-check the ID first'
