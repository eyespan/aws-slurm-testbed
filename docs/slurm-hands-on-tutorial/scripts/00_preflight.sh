#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
mkdir -p output

echo "== Slurm client availability =="
missing=0
for cmd in sbatch srun salloc squeue sinfo scancel scontrol; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '%-10s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '%-10s MISSING\n' "$cmd"
    missing=1
  fi
done

if (( missing )); then
  echo "One or more core commands are missing. Run this on your site's Slurm login node." >&2
  exit 1
fi

echo
echo "== User and host =="
printf 'User: '; id -un
printf 'Host: '; hostname
printf 'Slurm version: '; srun --version || true

echo
echo "== Partitions and nodes =="
sinfo || true

echo
echo "== Optional commands =="
for cmd in sacct sacctmgr sreport sstat sprio sshare sdiag sview sbcast sattach strigger scrontab sh5util slurmrestd; do
  command -v "$cmd" >/dev/null 2>&1 && printf '%-12s available\n' "$cmd" || printf '%-12s not found on PATH\n' "$cmd"
done

echo
echo "Preflight finished. A command being installed does not guarantee that your account has permission to use it."
