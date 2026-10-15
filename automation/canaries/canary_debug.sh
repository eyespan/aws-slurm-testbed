#!/usr/bin/env bash
# Warm canary: submit to debug partition every 5 minutes (Task 20)
set -euo pipefail
PARTITION="${PARTITION:-debug}"
START=$(date +%s)
JOB=$(sbatch --parsable --partition="$PARTITION" --time=00:02:00 \
  --wrap='echo canary-ok; hostname' --output=/shared/canary/debug-%j.out 2>/dev/null || true)
if [[ -z "${JOB:-}" ]]; then
  aws cloudwatch put-metric-data --namespace HPC/Slurm \
    --metric-name canary_job_start_seconds --value 999 \
    --dimensions Partition="$PARTITION" --unit Seconds 2>/dev/null || true
  exit 1
fi
for i in $(seq 1 24); do
  st=$(squeue -j "$JOB" -h -o '%T' 2>/dev/null || true)
  [[ -z "$st" ]] && break
  sleep 5
done
END=$(date +%s)
LATENCY=$((END - START))
aws cloudwatch put-metric-data --namespace HPC/Slurm \
  --metric-name canary_job_start_seconds --value "$LATENCY" \
  --dimensions Partition="$PARTITION" --unit Seconds 2>/dev/null || true
echo "canary debug job=$JOB latency=${LATENCY}s"
