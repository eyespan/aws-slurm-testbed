#!/bin/bash
#SBATCH --job-name=slurm-tutorial-cancel
#SBATCH --output=output/cancel-%j.out
#SBATCH --error=output/cancel-%j.err
#SBATCH --time=00:10:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=128M

set -eu
echo "Cancellation demo job started at $(date)"
echo "Job ID: ${SLURM_JOB_ID:-unset}"
echo "This job intentionally sleeps for up to 8 minutes."
sleep 480
echo "The cancellation demo finished without being cancelled."
