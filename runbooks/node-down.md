# Runbook: Node DOWN

## Trigger
sinfo shows node DOWN or resume_failures metric > 0.

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
1. `hpcops diagnose-node <node>`
2. Inspect resume events for InsufficientInstanceCapacity or IAM errors.
3. Clear reason after fix: `scontrol update NodeName=<node> State=RESUME`
4. For static debug node, reboot via SSM or console if needed.
