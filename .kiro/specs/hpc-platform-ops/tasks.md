# Implementation Plan: HPC Platform Operations Test Bed

## How to use this plan

Legend for each task:

- **[LOCAL]** can be done without a sandbox session. **[SANDBOX]** needs a live session.
- **[Q]** suits Qwen3 Coder Next (cheap, bulk work). **[S]** suits Claude Sonnet 4.5 (use sparingly, for design-critical work).

Run one task per Kiro prompt. After each task run the quality gates (`make lint test`) before moving on. Keep a reserve of credits for the final debugging stage.

---

## Phase 0: Foundation and guardrails

- [x] 1. Scaffold the repository **[LOCAL] [Q]**
  - Create the folder layout from `structure.md` with `.gitignore` (state files, credentials, `.terraform`), `README.md` stub, `Makefile` with targets `preflight up down plan apply drift test lint evidence`.
  - Add `pre-commit` config running fmt, tflint, shellcheck and ruff.
  - _Requirements: 2.1, 13.1_

- [x] 2. Implement sandbox guardrails **[LOCAL] [Q]**
  - Terraform variables with `validation` blocks: instance type allow-list, region allow-list, maximum instance count.
  - Python policy check script that scans plan JSON for disallowed types, regions and unavailable services; unit tests included.
  - `docs/instance-budget.md` with the table from `design.md`.
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 3. Write the preflight and lifecycle scripts **[LOCAL] [Q]**
  - `make preflight`: verify identity (`cloud_user`), region, running instance count vs budget.
  - `make up` and `make down`: apply, and export evidence then destroy tagged resources.
  - Mandatory tags `Project`, `Env`, `Session` via provider `default_tags`.
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 4. Bootstrap security base: KMS, CloudTrail, Config **[LOCAL] [Q]**
  - `terraform/bootstrap`: customer-managed KMS keys with rotation, encrypted S3 log bucket, CloudTrail with log file validation, Config recorder and the five rules from the design.
  - _Requirements: 11.1, 11.2_

---

## Phase 1: Network and storage

- [x] 5. Network module **[LOCAL] [Q]**
  - VPC, two public and two private subnets, NAT gateway, route tables, security groups per tier, S3 gateway endpoint, flow logs.
  - Route 53 private hosted zone `hpc.internal`.
  - Do not add interface endpoints, Transit Gateway or PrivateLink.
  - _Requirements: 3.1, 3.2_

- [x] 6. Network diagnostic runbook and ADRs **[LOCAL] [Q]**
  - `runbooks/connectivity-triage.md` (security groups, routes, NACLs, DNS, flow logs).
  - DESIGN-ONLY ADRs for Transit Gateway, Direct Connect and PrivateLink.
  - _Requirements: 3.3, 3.4, 16.1, 16.2_

- [x] 7. Storage module (EFS baseline) **[LOCAL] [Q]**
  - Encrypted EFS with mount targets in both AZs, access points for `/shared` and `/home`, alarms on burst credits and throughput.
  - _Requirements: 6.1, 6.4_

- [x] 8. Optional FSx for Lustre module **[LOCAL] [Q]**
  - Smallest scratch deployment behind a `enable_fsx` flag (default false) with `make fsx-up` and `make fsx-down`, plus a short throughput benchmark script.
  - _Requirements: 6.2, 6.3_

---

## Phase 2: Slurm platform

- [x] 9. Node image recipe **[LOCAL] [Q]**
  - Image Builder components for AL2023 hardening, Slurm build from source (pinned `slurm_version`), munge, node_exporter, CloudWatch agent.
  - Pipeline definition and weekly schedule.
  - _Requirements: 4.4, 10.1_

- [x] 10. Controller module and config templates **[LOCAL] [S]**
  - Controller instance (t3.medium), EFS state dir, MariaDB and `slurmdbd`, templates for `slurm.conf`, `slurmdbd.conf`, `cgroup.conf`.
  - Munge key in Secrets Manager, IAM role with least privilege.
  - Partition and node definitions for `debug` (static) and `std` (cloud).
  - _Requirements: 4.1, 4.3, 4.4, 11.1_

- [ ] 11. Login node and static debug node **[LOCAL] [Q]**
  - Login node (t3.small) and static `debug` node (t3.micro) joined to the cluster, EFS mounted, user provisioning from a YAML file.
  - _Requirements: 4.2_

- [ ] 12. Resume and suspend programs **[LOCAL] [S]**
  - `slurm_resume.py` and `slurm_suspend.py`: launch from the launch template, tag, register DNS, log structured events, mark nodes DOWN on failure, emit `resume_latency_seconds`.
  - Launch template resolves AMI from `resolve:ssm:/hpc-testbed/ami/compute/current`.
  - pytest tests with moto covering success, capacity failure and idempotency.
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 10.4_

- [ ] 13. Scheduler smoke tests **[LOCAL] [Q]**
  - Shell and Python tests: submit, run, complete, cancel, plus a cold-start test on `std`.
  - _Requirements: 4.3, 7.4_

- [ ] 14. First live deployment: network, controller, login, debug node **[SANDBOX] [Q]**
  - Run `make preflight up`, then the smoke tests. Record issues in `docs/sandbox-notes.md`.
  - _Requirements: 2.1, 4.1, 4.2, 4.3_

- [ ] 15. Live elastic compute test **[SANDBOX] [Q]**
  - Submit jobs to `std`, confirm nodes resume, run, then suspend. Record resume latency and tune `SuspendTime` and `ResumeTimeout`. Record the limits you hit (instance cap, Spot, large families).
  - _Requirements: 5.1, 5.2, 5.5_

---

## Phase 3: Operations tooling

- [ ] 16. Ops CLI **[LOCAL] [S]**
  - `hpcops` package with `drain-node`, `diagnose-job`, `diagnose-node`, `requeue-stuck`. Dry-run by default, `--yes` for destructive actions, JSON line log to `evidence/ops-log.jsonl`.
  - Unit tests with moto and mocked Slurm command output.
  - _Requirements: 7.1, 7.2, 7.3_

- [ ] 17. Scheduler runbooks **[LOCAL] [Q]**
  - Runbooks from `_template.md`: stuck job, failed job, node down, node drain and reboot, controller restart, Slurm upgrade and rollback.
  - _Requirements: 4.4, 7.1, 15.1_

- [ ] 18. Rehearse the ops procedures **[SANDBOX] [Q]**
  - Run each runbook once, log the result under `incidents/` or `evidence/`.
  - _Requirements: 7.2, 15.2_

---

## Phase 4: Observability

- [ ] 19. Monitoring node and dashboards **[LOCAL] [Q]**
  - Monitoring instance with Prometheus, Slurm exporter, node_exporter targets, Grafana with provisioned dashboards (queue wait, job start latency, node states, storage).
  - _Requirements: 8.1_

- [ ] 20. Probes, canaries and custom metrics **[LOCAL] [Q]**
  - Probe Lambda for the portal and port checks, canary job scripts on `debug` (every 5 minutes) and `std` (hourly), metrics pushed to CloudWatch.
  - _Requirements: 8.2, 5.4_

- [ ] 21. Alarms with enforced metadata **[LOCAL] [Q]**
  - CloudWatch alarms and SNS topic for each SLI. Every alarm tagged `severity`, `sli`, `runbook`.
  - CI check that fails when a tag or runbook link is missing.
  - _Requirements: 8.3, 15.3_

- [ ] 22. Status portal and ALB **[LOCAL] [Q]**
  - Read-only FastAPI or Flask service with `/healthz`, shows `sinfo` and recent canaries, fronted by an ALB with health checks.
  - _Requirements: 9.1_

- [ ] 23. Observability go-live and tuning **[SANDBOX] [Q]**
  - Deploy, generate load and failures, tune thresholds, record changes in `docs/alert-tuning.md`.
  - _Requirements: 8.1, 8.2, 8.4_

---

## Phase 5: Image, patch and identity

- [ ] 24. Inspector findings and AMI promotion **[LOCAL] [S]**
  - `inspector-ticket` Lambda, `image-promote` script (smoke test, then SSM parameters `current` and `previous`), `make ami-rollback`.
  - _Requirements: 10.2, 10.4_

- [ ] 25. Patch windows **[LOCAL] [Q]**
  - Patch Manager baseline and maintenance window for static nodes, drain-patch-verify-rejoin procedure and runbook.
  - _Requirements: 10.3_

- [ ] 26. Directory and access (try, with fallback) **[LOCAL] [Q]**
  - Simple AD and SSSD module behind `enable_directory` (default false). Local-user fallback. Optional NICE DCV install script. Record outcomes in `docs/sandbox-notes.md`.
  - _Requirements: 9.2, 9.3_

- [ ] 27. Image and patch live run **[SANDBOX] [Q]**
  - Build an AMI (uses the 2 reserved instance slots), promote it, roll a node, roll back. Run one patch window.
  - _Requirements: 10.1, 10.2, 10.3, 10.4_

---

## Phase 6: Security evidence

- [ ] 28. Security services and evidence collector **[LOCAL] [S]**
  - GuardDuty and Security Hub enabled (this account only).
  - `evidence.py` and `make evidence`: IAM, KMS, CloudTrail validation, Config compliance, patch state, AMI inventory, with SHA-256 manifest.
  - Unit tests with moto.
  - _Requirements: 11.2, 11.3, 11.4_

- [ ] 29. Evidence run **[SANDBOX] [Q]**
  - Run `make evidence`, review the pack, fix any non-compliant Config rule, commit a sample pack.
  - _Requirements: 11.3, 11.4_

---

## Phase 7: Resilience and incidents

- [ ] 30. FIS experiment templates **[LOCAL] [S]**
  - `fis-experiments` module: node stop, subnet connectivity disruption, DNS failure via SSM document, optional controller stop. Each at most 5 minutes with stop conditions on alarms.
  - _Requirements: 12.2, 12.3_

- [ ] 31. Incident process and PIR template **[LOCAL] [Q]**
  - `docs/incident-lifecycle.md`, `incidents/templates/pir.md`, severity matrix, communication templates, corrective-action tracker format.
  - _Requirements: 12.1, 12.4_

- [ ] 32. Run the experiments and write the PIRs **[SANDBOX] [Q]**
  - Run each experiment (total FIS action time must stay under 20 minutes), follow the runbooks, write a blameless PIR for each with tracked actions.
  - _Requirements: 12.2, 12.3, 12.4_

---

## Phase 8: CI/CD, reporting and design-only artefacts

- [ ] 33. GitHub Actions static gates **[LOCAL] [Q]**
  - Workflow for fmt, validate, tflint, checkov, shellcheck, ruff, pytest, policy checks, runbook-link and alert-tag checks.
  - _Requirements: 13.1, 1.4, 15.3_

- [ ] 34. Plan, apply and drift targets **[LOCAL] [Q]**
  - `make plan`, `make apply` (with confirmation), `make drift` (`-detailed-exitcode`), outputs stored in `evidence/`. `docs/rollback.md`.
  - _Requirements: 13.2, 13.3, 13.4_

- [ ] 35. Service report and capacity forecast **[LOCAL] [S]**
  - `service_report.py`: availability vs SLO, incidents, changes, capacity trend, utilisation anomalies, limitation note about missing billing data. Sample report committed.
  - _Requirements: 14.1, 14.2, 14.3, 14.4_

- [ ] 36. Design-only ADRs **[LOCAL] [Q]**
  - ADRs and diagrams for AWS PCS, AWS RES, EFA networking, and the production OIDC deploy pipeline. Each states target design, why not built, and the sandbox substitute.
  - _Requirements: 4.5, 9.4, 16.1, 16.2_

---

## Phase 9: Finish

- [ ] 37. Final end-to-end run **[SANDBOX] [Q]**
  - `make up`, smoke tests, one canary cycle, one drain, one fault experiment, `make evidence`, `make down`. Fix what breaks.
  - _Requirements: 2.1, 2.2, 4.3, 7.4, 12.2_

- [ ] 38. Portfolio README **[LOCAL] [S]**
  - Architecture summary, what is built vs simulated vs design-only, sample SLO dashboard screenshots, sample PIR, sample service report, how to reproduce.
  - _Requirements: 16.1_

---

## Rough credit plan (50 credits)

These are starting guesses; adjust after your first few prompts.

| Group | Tasks | Model | Share of credits |
|---|---|---|---|
| Design-critical code | 10, 12, 16, 24, 28, 30, 35 | Sonnet 4.5 | about 60% |
| Everything else | remaining tasks | Qwen3 Coder Next | about 15% |
| Fixes and live-session debugging | Phases 2 to 7 | Qwen first, Sonnet if stuck | about 15% |
| Reserve | final polish and README | Sonnet | about 10% |
