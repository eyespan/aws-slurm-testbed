#!/bin/bash
#SBATCH --job-name=slurm-tutorial-second
#SBATCH --output=output/dependency-second-%j.out
#SBATCH --error=output/dependency-second-%j.err
#SBATCH --time=00:02:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=128M

set -eu
echo "This dependent job runs only after its parent succeeds."
echo "Parent job ID: ${SLURM_JOB_DEPENDENCY:-see submission command}"
echo "Child job ID: ${SLURM_JOB_ID:-unset}"
