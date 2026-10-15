#!/bin/bash
#SBATCH --job-name=slurm-tutorial-first
#SBATCH --output=output/dependency-first-%j.out
#SBATCH --error=output/dependency-first-%j.err
#SBATCH --time=00:02:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=128M

set -eu
echo "Dependency parent started: $(date)"
sleep 3
echo "Dependency parent succeeded"
