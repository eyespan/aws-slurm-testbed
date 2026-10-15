# Runbook: Failed job

## Trigger
Job exits non-zero or NodeFail; user or canary reports failure.

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
1. `hpcops diagnose-job <jobid>` and inspect ExitCode / Reason.
2. Check slurmd logs on the node and CloudWatch log groups.
3. Requeue if transient: `scontrol requeue <jobid>`.
4. If node-related, drain and replace (static) or let suspend/resume cycle (cloud).
