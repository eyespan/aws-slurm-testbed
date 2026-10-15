#!/bin/bash
#SBATCH --job-name=slurm-tutorial-hello
#SBATCH --output=output/hello-%j.out
#SBATCH --error=output/hello-%j.err
#SBATCH --time=00:02:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=128M

set -eu

echo "Hello from a Slurm batch job"
echo "Date: $(date)"
echo "Host: $(hostname)"
echo "Job ID: ${SLURM_JOB_ID:-unset}"
echo "Job name: ${SLURM_JOB_NAME:-unset}"
echo "Partition: ${SLURM_JOB_PARTITION:-unset}"
echo "Node list: ${SLURM_JOB_NODELIST:-unset}"
echo "CPUs per task: ${SLURM_CPUS_PER_TASK:-unset}"
echo "Working directory: $(pwd)"
sleep 2
echo "Job finished successfully"
