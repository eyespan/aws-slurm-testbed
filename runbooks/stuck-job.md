# Runbook: Stuck job

## Trigger
Job remains in CF/CG/PD beyond expected start latency; alert on queue wait or canary failure.

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
1. `hpcops diagnose-job <jobid>`
2. If node is DOWN: `hpcops diagnose-node <node>` and remediate (resume capacity or mark resume failure).
3. If stuck in CF/CG > 30m: `hpcops requeue-stuck --minutes 30 --yes`
4. If repeatedly failing, drain the node: `hpcops drain-node <node> --reason "stuck jobs" --yes`
