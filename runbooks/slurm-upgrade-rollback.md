# Runbook: Slurm upgrade and rollback

## Trigger
Planned upgrade of pinned slurm_version or emergency rollback.

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
1. Build new AMI via Image Builder with updated `slurm_version`.
2. Promote AMI (`image-promote`) after smoke test.
3. Roll static nodes one at a time (drain → replace → verify).
4. Rollback: `make ami-rollback` swaps SSM current/previous, then re-roll nodes.
