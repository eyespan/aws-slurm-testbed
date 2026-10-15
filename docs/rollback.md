# Rollback procedures

## Terraform
1. Identify last known good state (`evidence/` plans and state backups).
2. `terraform plan -destroy` for the failed module only when safe.
3. Prefer forward-fix: re-apply fixed config rather than state surgery.
4. AMI rollback: `make ami-rollback` swaps SSM `/hpc-testbed/ami/compute/current` and `previous`.

## Slurm
- Controller: restore `slurm.conf` from git; restart slurmctld; confirm job recovery from EFS state.
- Node image: drain → terminate/replace with previous AMI → resume.

## Evidence
Always run `make evidence` after rollback and attach the pack to the incident.
