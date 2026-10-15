# Runbook: Drain–patch–verify–rejoin for static nodes

## Trigger
Patch Manager maintenance window, or manual security patching of controller / login / monitoring.

## Diagnosis
1. Confirm node role (`controller`, `login`, `monitoring`).
2. Check open jobs: `squeue -w <node>` (login/controller may not run slurmd jobs the same way).

## Action
1. **Drain** (compute-affecting nodes): `hpcops drain-node <node> --reason "patch window" --yes`
2. Wait until jobs complete or requeue them.
3. **Patch** via SSM: `AWS-RunPatchBaseline` Operation=Install, or wait for the maintenance window task.
4. **Verify**: reboot if required; `systemctl is-active slurmctld slurmd munge` as applicable; `scontrol ping`.
5. **Rejoin**: `scontrol update NodeName=<node> State=RESUME` when drained.

## Verification
- Node returns to IDLE/ALLOC.
- Canary on `debug` succeeds.
- Patch compliance in Systems Manager is COMPLIANT.

## Escalation
If patch breaks Slurm, roll back AMI on that node and open a SEV-2 incident.
