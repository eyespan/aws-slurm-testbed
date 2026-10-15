# Task progress summary

## Completed (all LOCAL tasks)

| Task | Description |
|---|---|
| 1–13 | Foundation through smoke tests |
| 16–17 | Ops CLI + scheduler runbooks |
| 19 | Monitoring node (Prometheus/Grafana) |
| 20 | Probe Lambda + canary scripts |
| 21 | CloudWatch alarms with severity/sli/runbook tags |
| 22 | Status portal (Flask/stdlib) + ALB module |
| 24 | image_promote / ami-rollback + inspector-ticket Lambda |
| 25 | Patch baseline + maintenance window + runbook |
| 26 | Identity module (Simple AD optional; YAML users default) |
| 28 | Evidence collector (+ patch/AMI inventory) |
| 30 | FIS experiment templates + DNS failure SSM doc |
| 31 | Incident lifecycle + PIR template |
| 33–34 | GitHub Actions CI + plan/apply/drift |
| 35 | service_report.py + sample report |
| 36 | Design-only ADRs 004–007 |
| 38 | Portfolio README |

## Remaining SANDBOX-only (need live AWS session)

| Task | Action |
|---|---|
| 14 | First live deploy: `make preflight up` + smoke |
| 15 | Live elastic compute test on `std` |
| 18 | Rehearse each ops runbook once |
| 23 | Observability go-live + alert tuning log |
| 27 | AMI build/promote/roll/rollback + patch window |
| 29 | `make evidence` live run + fix Config gaps |
| 32 | Run FIS experiments (≤20 min) + write PIRs |
| 37 | Full E2E cycle |

See `docs/sandbox-notes.md` for TRY path outcomes to record during live runs.
