#!/usr/bin/env bash
set -eu
echo "== One task =="
srun --ntasks=1 hostname
echo
echo "== Two tasks, labelled output =="
srun --ntasks=2 --cpus-per-task=1 --label hostname
echo
echo "If your site requires an account or partition, add --account=... and/or --partition=... to these srun commands."
