# Runbook: Node drain and reboot

## Trigger
Maintenance or unhealthy node requiring reboot.

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
1. `hpcops drain-node <node> --reason "reboot" --yes`
2. Wait until jobs drain (`squeue -w <node>` empty).
3. Reboot (SSM `AWS-RunShellScript` or EC2 reboot).
4. After healthy: `scontrol update NodeName=<node> State=RESUME`
