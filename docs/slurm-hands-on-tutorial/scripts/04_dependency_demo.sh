#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
mkdir -p output
parent=$(sbatch --parsable jobs/dependency-first.sbatch)
parent=${parent%%;*}
child=$(sbatch --parsable --dependency="afterok:${parent}" jobs/dependency-second.sbatch)
child=${child%%;*}
echo "Parent job: $parent"
echo "Dependent job: $child"
echo "Inspect both: squeue -j ${parent},${child}"
echo "After completion: sacct -j ${parent},${child} --format=JobID,JobName,State,ExitCode,Elapsed"
