# Runbook: Controller restart

## Trigger
slurmctld unresponsive or planned restart.

## Diagnosis
1. Confirm alert / symptom is still active.
2. Gather context:
   - `sinfo -N -l`
   - `squeue -l`
   - `scontrol show node <name>` / `scontrol show job <id>`
   - CloudWatch metrics and recent structured resume/suspend events
3. Check `evidence/ops-log.jsonl` for recent operator actions.

## Action
See steps specific to this scenario below.

## Verification
- Alert clears or SLI returns within SLO.
- Node returns to IDLE/ALLOC or job reaches a terminal state.

## Escalation
If unresolved after 30 minutes, escalate to platform on-call and open an incident using `incidents/templates/pir.md`.

---
## Action
1. Confirm StateSaveLocation on EFS is healthy.
2. `systemctl stop slurmctld` then `systemctl start slurmctld` on controller.
3. `scontrol ping` and verify queued jobs recovered.
4. Check slurmdbd/MariaDB connectivity.
