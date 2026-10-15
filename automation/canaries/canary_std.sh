#!/usr/bin/env bash
# Cold canary: submit to std partition hourly (includes resume latency) — Task 20
set -euo pipefail
PARTITION="${PARTITION:-std}"
START=$(date +%s)
mkdir -p /shared/canary
JOB=$(sbatch --parsable --partition="$PARTITION" --time=00:05:00 \
  --wrap='echo canary-std-ok; hostname' --output=/shared/canary/std-%j.out 2>/dev/null || true)
if [[ -z "${JOB:-}" ]]; then
  aws cloudwatch put-metric-data --namespace HPC/Slurm \
    --metric-name canary_job_start_seconds --value 999 \
    --dimensions Partition="$PARTITION" --unit Seconds 2>/dev/null || true
  exit 1
fi
# Allow up to ResumeTimeout + run time (~10 min)
for i in $(seq 1 72); do
  st=$(squeue -j "$JOB" -h -o '%T' 2>/dev/null || true)
  [[ -z "$st" ]] && break
  sleep 5
done
END=$(date +%s)
LATENCY=$((END - START))
aws cloudwatch put-metric-data --namespace HPC/Slurm \
  --metric-name canary_job_start_seconds --value "$LATENCY" \
  --dimensions Partition="$PARTITION" --unit Seconds 2>/dev/null || true
echo "canary std job=$JOB latency=${LATENCY}s"
