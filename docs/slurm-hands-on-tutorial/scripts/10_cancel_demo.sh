#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
mkdir -p output
job_id=$(sbatch --parsable jobs/cancel-demo.sbatch)
job_id=${job_id%%;*}
echo
echo "Submitted dedicated cancellation demo job: $job_id"
echo "Inspect it: squeue -j $job_id"
echo "When ready, cancel ONLY this ID with:"
printf 'scancel %q\n' "$job_id"
echo "Then verify: sacct -j $job_id --format=JobID,JobName,State,ExitCode,Elapsed"
echo "This script does not cancel anything automatically."
