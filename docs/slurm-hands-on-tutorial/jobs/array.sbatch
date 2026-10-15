#!/bin/bash
#SBATCH --job-name=slurm-tutorial-array
#SBATCH --output=output/array-%A_%a.out
#SBATCH --error=output/array-%A_%a.err
#SBATCH --time=00:02:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=128M

set -eu

: "${SLURM_ARRAY_TASK_ID:?This script must be submitted as a Slurm array}"
echo "Array job ID: ${SLURM_ARRAY_JOB_ID:-unset}"
echo "Array task ID: ${SLURM_ARRAY_TASK_ID}"
echo "Input number: ${SLURM_ARRAY_TASK_ID}"
sleep 1
echo "Task ${SLURM_ARRAY_TASK_ID} complete"
