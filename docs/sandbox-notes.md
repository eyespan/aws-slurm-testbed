# Sandbox notes

Record outcomes of TRY paths and SANDBOX task runs here.

## Directory services (Task 26)
- Default: `enable_directory = false`
- Fallback: local users from `config/users/users.yaml` provisioned on login node
- If Simple AD is attempted and blocked, note error codes and keep YAML users

## NICE DCV (Task 26 / Req 9)
- TRY on login node; may require larger instance or licensing
- If blocked: SSH-only access remains supported

## FSx for Lustre (Task 8)
- Optional via `make fsx-up` / `make fsx-down`
- If blocked or unaffordable: continue with EFS only

## Live tasks requiring a cloud session
| Task | Action |
|---|---|
| 14 | `make preflight up` then smoke tests |
| 15 | Submit to `std`, measure resume latency, tune SuspendTime |
| 18 | Execute each runbook once; log under `incidents/` or `evidence/` |
| 23 | Deploy observability, generate load, tune alarms → `docs/alert-tuning.md` |
| 27 | Build AMI, promote, roll node, rollback, one patch window |
| 29 | `make evidence`, fix Config non-compliance, commit sample pack |
| 32 | Run FIS templates (≤20 min total), write PIRs |
| 37 | Full E2E: up → smoke → canary → drain → FIS → evidence → down |
