#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
mkdir -p output
job_id=$(sbatch --parsable jobs/hello.sbatch)
job_id=${job_id%%;*}
echo "Submitted hello job: $job_id"
echo "Monitor: squeue -j $job_id"
echo "Inspect details: scontrol show job $job_id"
echo "After it finishes: sacct -j $job_id --format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,MaxRSS"
