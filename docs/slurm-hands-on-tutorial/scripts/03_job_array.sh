#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
mkdir -p output
job_id=$(sbatch --parsable --array=1-5 jobs/array.sbatch)
job_id=${job_id%%;*}
echo "Submitted array: $job_id"
echo "Watch it: squeue -j $job_id"
echo "Outputs: output/array-${job_id}_*.out"
