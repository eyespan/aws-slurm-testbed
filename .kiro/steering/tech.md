---
inclusion: always
---

# Technology and conventions

## Stack
- **IaC:** Terraform (OpenTofu-compatible HCL). Pin provider and module versions. Avoid features that break OpenTofu compatibility.
- **Automation:** Python 3.12 (boto3, pytest) and Bash (`set -euo pipefail`, shellcheck-clean).
- **Scheduler:** Slurm on Amazon Linux 2023 (default, no Marketplace subscription needed). Rocky Linux 9 is a stretch goal only, because its AMIs come from AWS Marketplace, which the sandbox may block. `slurmctld` on the head node, `slurmdbd` with MariaDB for accounting, cloud bursting via Slurm power-saving (`ResumeProgram` / `SuspendProgram` calling EC2). Pin the Slurm version in one variable.
- **Observability:** CloudWatch (logs, metrics, alarms, synthetics-style probes via Lambda or scripts), plus Prometheus, a Slurm exporter, node_exporter and Grafana self-hosted on the monitoring node.
- **Images and patching:** EC2 Image Builder, Inspector, Systems Manager Patch Manager.
- **Security and audit:** IAM least privilege, KMS customer-managed keys, CloudTrail with log file validation, AWS Config rules, GuardDuty, Security Hub.
- **Chaos:** AWS Fault Injection Simulator, within the 20-minute limit.
- **CI/CD:** GitHub Actions for lint, validate, plan and apply. Terraform plan review, drift detection on a schedule, and a documented rollback path.
- **Quality gates:** `terraform fmt`, `terraform validate`, `tflint`, `checkov`, `shellcheck`, `ruff`, `pytest`, `pre-commit`.

## Conventions
- Small, composable Terraform modules. One concern per module, with documented inputs and outputs.
- No hardcoded account IDs, ARNs or regions. Everything comes from variables and data sources.
- Scripts are idempotent and safe to re-run. Destructive operations require an explicit flag.
- Every alert links to a runbook. Every runbook lists its trigger, diagnosis, action, verification and escalation.
- Commit messages use conventional commits. Decisions go in `docs/adr/` as numbered ADRs.
