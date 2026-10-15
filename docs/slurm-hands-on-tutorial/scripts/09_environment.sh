#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
mkdir -p output
job_id=$(sbatch --parsable jobs/hello.sbatch)
job_id=${job_id%%;*}
echo "Submitted job $job_id. Its output will print selected Slurm environment variables."
echo "Once it completes, inspect output/hello-${job_id}.out"
echo "The job script prints SLURM_JOB_ID, SLURM_JOB_NAME, SLURM_JOB_PARTITION, SLURM_JOB_NODELIST and SLURM_CPUS_PER_TASK."
echo "Outside a job, many SLURM_* variables are unset."
