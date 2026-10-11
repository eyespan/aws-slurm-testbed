---
inclusion: always
---

# Sandbox constraints (Pluralsight AWS cloud sandbox)

Source: Pluralsight Help Center, "AWS cloud sandbox" (page updated 25 June 2026).
The list can change. Re-check it at the start of each session and update this file.

## Hard limits: never generate code that violates these

- **Regions:** `us-east-1` and `us-west-2` only. Default to `us-east-1`.
- **Identity:** work as the `cloud_user` role with temporary credentials. No billing, cost data or budgets access.
- **EC2:**
  - Instance types: `t2`, `t3`, `t3a`, `t4g`, in `micro`, `small` or `medium` only.
  - Maximum 9 instances at once. Stopped instances count; terminated ones do not. EC2 Image Builder build instances count too.
  - Maximum 100 GB per volume. Default tenancy only. No Spot.
- **Lambda:** maximum 10 functions, maximum 2048 MB memory each. No durable functions or MicroVMs.
- **Fargate:** maximum 4 running tasks, 2048 CPU and 4096 MB memory per task.
- **RDS:** `t3` or `t4g` micro/small/medium, 50 GB maximum, no provisioned IOPS.
- **EKS:** standard-support Kubernetes versions only. Extended support is not permitted.
- **FSx:** allowed except FileCache. Lustre minimum capacity is large, so create it for short sessions only and expect it may be blocked by quota.
- **Fault Injection Simulator:** maximum 20 minutes of action time per sandbox session.
- **Systems Manager:** no custom inventories.
- **Security Hub:** this account only. No member invitations.
- **Other:** Route 53 (no Profiles, Recovery or Domains), ACM (no exportable certificates), Backup (no legal holds), CodeBuild (small/medium general instances only).

## Services that will not work: never use them

- Transit Gateway, Direct Connect, PrivateLink (and therefore **interface VPC endpoints**), Global Accelerator, Cloud WAN.
- AWS Organizations, Control Tower, IAM Access Analyzer.
- Budgets, Cost Explorer, Cost and Usage Reports.
- Marketplace subscriptions: the sandbox page gives them no support level. Assume unavailable and use Amazon-provided AMIs only.
- Managed Grafana and Managed Service for Prometheus (self-host instead). AWS VPN is not supported.
- AWS PCS and RES are **not listed** on the sandbox page. Treat them as unavailable. EFA-capable instance families are not allowed.

## Rules for the agent

1. If a request needs a disallowed service, instance type or region, do not generate it. Name the constraint, propose the closest sandbox-feasible substitute, and mark the original as **DESIGN-ONLY** (an ADR plus a diagram, no code).
2. Every Terraform instance type must pass a `validation` block restricting it to the allowed families and sizes. Keep the allow-list in one variable.
3. Keep a running instance budget in `docs/instance-budget.md`. Reserve 2 of the 9 slots for Image Builder build/test instances. Default allocation: head, login, monitoring, up to 4 compute.
4. Treat the sandbox as ephemeral. Every resource must be created by code and destroyed by `make down`. Export evidence (reports, logs, post-incident reviews) into the repo before teardown.
5. Never commit credentials. Use `AWS_PROFILE=sandbox` or environment variables only. Keep Terraform state local and gitignored.
6. Tag all resources: `Project=hpc-testbed`, `Env=sandbox`, `Session=<id>`.
7. Do not claim a feature runs on PCS, RES or EFA anywhere in the docs or code. State what is simulated and how it differs from the production target.
