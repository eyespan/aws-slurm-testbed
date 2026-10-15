#!/usr/bin/env bash
# Scheduler smoke tests (Task 13)
# Run on the login node against a live cluster: submit, run, complete, cancel, cold-start.
set -euo pipefail

PARTITION_DEBUG="${PARTITION_DEBUG:-debug}"
PARTITION_STD="${PARTITION_STD:-std}"
WORKDIR="${WORKDIR:-/shared/smoke}"
mkdir -p "$WORKDIR"

pass=0
fail=0

ok() { echo "PASS: $*"; pass=$((pass+1)); }
ko() { echo "FAIL: $*"; fail=$((fail+1)); }

echo "=== Slurm smoke tests ==="
echo "sinfo:"; sinfo || true

# 1. Submit and complete a trivial job on debug
JOB1=$(sbatch --parsable --partition="$PARTITION_DEBUG" --wrap='echo hello-smoke; sleep 2' --output="$WORKDIR/job1-%j.out")
if [[ -n "$JOB1" ]]; then
  ok "submitted debug job $JOB1"
else
  ko "submit debug job"
fi

# Wait for completion (max 3 min)
for i in $(seq 1 36); do
  st=$(squeue -j "$JOB1" -h -o '%T' 2>/dev/null || true)
  [[ -z "$st" || "$st" == "COMPLETED" ]] && break
  sleep 5
done
sacct -j "$JOB1" -n -o State 2>/dev/null | grep -q COMPLETED && ok "job $JOB1 completed" || ko "job $JOB1 did not complete"

# 2. Cancel a running/pending job
JOB2=$(sbatch --parsable --partition="$PARTITION_DEBUG" --wrap='sleep 120' --output="$WORKDIR/job2-%j.out")
scancel "$JOB2"
sleep 3
sacct -j "$JOB2" -n -o State 2>/dev/null | grep -Eq 'CANCELLED|COMPLETED' && ok "job $JOB2 cancelled" || ko "cancel $JOB2"

# 3. Cold-start on std (may take ResumeTimeout)
if sinfo -p "$PARTITION_STD" -h >/dev/null 2>&1; then
  JOB3=$(sbatch --parsable --partition="$PARTITION_STD" --wrap='hostname; sleep 5' --output="$WORKDIR/job3-%j.out")
  ok "submitted std job $JOB3 (cold start may apply)"
  for i in $(seq 1 72); do
    st=$(squeue -j "$JOB3" -h -o '%T' 2>/dev/null || true)
    [[ -z "$st" ]] && break
    sleep 5
  done
  sacct -j "$JOB3" -n -o State 2>/dev/null | grep -q COMPLETED && ok "std job $JOB3 completed" || ko "std job $JOB3 (may need elastic capacity)"
else
  echo "SKIP: partition $PARTITION_STD not configured"
fi

echo "=== Results: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
