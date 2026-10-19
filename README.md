# HPC Platform Operations Test Bed

> **Engineering Portfolio Project**
>
> A scaled-down, production-oriented Slurm HPC platform on AWS EC2 demonstrating scheduler operations, shared storage, image/patch lifecycle, SLIs and alerts, runbooks, audit evidence, fault injection, and service reporting.

Built for a Pluralsight-style AWS sandbox (instance cap 9, region allow-list, no TGW/PrivateLink/PCS).

**Repository:** https://github.com/eyespan/aws-slurm-testbed

---

## Table of contents

1. [Architecture](#architecture-built)
2. [Built vs TRY vs DESIGN-ONLY](#built-vs-try-vs-design-only)
3. [Quick start](#quick-start)
4. [Key make targets](#key-make-targets)
5. [Ops CLI](#ops-cli)
6. [Documentation index](#documentation-index)
7. [Repository map](#repository-map)
8. [Reproduce](#reproduce)
9. [Sandbox constraints](#sandbox-constraints)
10. [Repository](#repository)
11. [Credits & attribution](#credits--attribution)
12. [Licence](#licence)
13. [Disclaimer](#disclaimer)

---

## Architecture (built)

| Layer | What |
|-------|------|
| Network | VPC, 2 AZ public/private subnets, NAT, SGs, R53 `hpc.internal`, flow logs |
| Storage | Encrypted EFS `/shared` + `/home`; optional FSx Lustre (TRY) |
| Scheduler | Self-managed Slurm controller + slurmdbd; partitions `debug` (static) and `std` (cloud power-save) |
| Access | Login node (SSH + status portal), YAML local users (AD optional) |
| Elasticity | `slurm_resume.py` / `slurm_suspend.py` + launch template + SSM AMI pointer |
| Observability | Monitoring node (Prometheus/Grafana), CloudWatch alarms (tagged severity/sli/runbook), probe Lambda, canaries |
| Lifecycle | Image Builder components, `image_promote` / `ami-rollback`, Patch Manager window |
| Security | KMS, CloudTrail, Config rules, GuardDuty, Security Hub, `make evidence` |
| Resilience | FIS templates (node stop, controller stop, DNS failure SSM doc), incident/PIR process |

Full design diagram and decisions: [`.kiro/specs/hpc-platform-ops/design.md`](.kiro/specs/hpc-platform-ops/design.md)

---

## Built vs TRY vs DESIGN-ONLY

| Capability | Status |
|------------|--------|
| Self-managed Slurm + power-save | **Built** |
| EFS shared storage | **Built** |
| FSx Lustre | **TRY** (`make fsx-up`) |
| Simple AD | **TRY** (`enable_directory=true`) |
| AWS PCS | **DESIGN-ONLY** ([ADR 004](docs/adr/004-aws-pcs.md)) |
| AWS RES | **DESIGN-ONLY** ([ADR 005](docs/adr/005-aws-res.md)) |
| EFA networking | **DESIGN-ONLY** ([ADR 006](docs/adr/006-efa-networking.md)) |
| OIDC deploy pipeline | **DESIGN-ONLY** ([ADR 007](docs/adr/007-oidc-deploy-pipeline.md)) |
| Transit Gateway / DX / PrivateLink | **DESIGN-ONLY** ([ADRs 001–003](docs/adr/)) |

---

## Quick start

```bash
# Quality gates (no AWS required)
make lint test

# Live sandbox session — required order (AMI before instances)
make preflight
make foundation         # Phase 1: VPC, subnets, SGs, EFS, Image Builder pipeline
make ami-build          # Phase 2: run pipeline, wait, promote AMI to SSM (45–90 min)
make instances          # Phase 3: controller + login + debug (needs AMI)
make full               # Phase 4: monitoring, observability, portal, …

# … smoke tests, canaries, ops runbooks …
make evidence
make down
```

Shortcuts:

| Command | Effect |
|---------|--------|
| `make up` | foundation → ami-build → instances (not phase 4) |
| `make full` | Remaining modules after instances |
| `python3 scripts/deploy.py up --skip-ami` | Skip AMI when current AMI already in SSM |

> **Important:** The Image Builder *pipeline* is only *scheduled* (Sunday 02:00 UTC).  
> `terraform apply` does **not** execute it. Use `make ami-build` (or set `TF_VAR_build_ami_on_apply=true`) before relying on Slurm on the nodes.

End-to-end validation with session screenshots: **[docs/e2e-test.md](docs/e2e-test.md)**

---

## Key make targets

| Target | Purpose |
|--------|---------|
| `preflight` | Identity, region, capacity vs budget |
| `foundation` | Phase 1: bootstrap + network + storage + image_builder |
| `ami-build` | Phase 2: run Image Builder, wait, promote AMI to SSM |
| `instances` | Phase 3: controller + login + debug |
| `full` | Phase 4: monitoring, observability, portal, … |
| `up` | Ordered deploy: foundation → ami-build → instances |
| `down` | Destroy with evidence export |
| `plan` / `apply` / `drift` | Terraform (`apply` needs `CONFIRM=yes`) |
| `evidence` | Audit pack with SHA-256 manifest |
| `ami-promote` / `ami-rollback` | SSM AMI current/previous |
| `service-report` | Monthly-style availability/capacity report |
| `fsx-up` / `fsx-down` | Optional scratch filesystem |

---

## Ops CLI

```bash
python -m hpcops drain-node debug-1 --reason "maintenance"   # dry-run default
python -m hpcops drain-node debug-1 --reason "maintenance" --yes
python -m hpcops diagnose-job 12345
python -m hpcops diagnose-node std-1
python -m hpcops requeue-stuck --minutes 30
```

Package: [`automation/python/hpcops/`](automation/python/hpcops/)

---

## Documentation index

### Specs (product intent)

| Doc | Description |
|-----|-------------|
| [`.kiro/specs/hpc-platform-ops/requirements.md`](.kiro/specs/hpc-platform-ops/requirements.md) | Requirements |
| [`.kiro/specs/hpc-platform-ops/design.md`](.kiro/specs/hpc-platform-ops/design.md) | Architecture, components, SLIs, testing strategy |
| [`.kiro/specs/hpc-platform-ops/tasks.md`](.kiro/specs/hpc-platform-ops/tasks.md) | Task breakdown (LOCAL / SANDBOX / TRY) |

### Steering

| Doc | Description |
|-----|-------------|
| [`.kiro/steering/product.md`](.kiro/steering/product.md) | Product framing |
| [`.kiro/steering/tech.md`](.kiro/steering/tech.md) | Tech choices |
| [`.kiro/steering/structure.md`](.kiro/steering/structure.md) | Repo layout |
| [`.kiro/steering/sandbox-constraints.md`](.kiro/steering/sandbox-constraints.md) | Sandbox limits and allow-lists |

### Operations & runbooks (`docs/`)

| Doc | Description |
|-----|-------------|
| [docs/e2e-test.md](docs/e2e-test.md) | **End-to-end test guide** (checklist + screenshots) |
| [docs/controller-operations.md](docs/controller-operations.md) | Controller ops |
| [docs/login-node-operations.md](docs/login-node-operations.md) | Login node ops |
| [docs/instance-budget.md](docs/instance-budget.md) | Instance cap and role sizes |
| [docs/incident-lifecycle.md](docs/incident-lifecycle.md) | Severity, triage, escalation, PIR |
| [docs/rollback.md](docs/rollback.md) | Infra and AMI rollback |
| [docs/alert-tuning.md](docs/alert-tuning.md) | Alarm threshold change log |
| [docs/sandbox-notes.md](docs/sandbox-notes.md) | TRY path outcomes (FSx, AD, DCV) |
| [docs/service-reports/sample-report.md](docs/service-reports/sample-report.md) | Sample service report |
| [docs/TASK_PROGRESS.md](docs/TASK_PROGRESS.md) | Task progress notes |
| [docs/IMPLEMENTATION_SUMMARY_TASK2.md](docs/IMPLEMENTATION_SUMMARY_TASK2.md) | Early implementation summary |

### Architecture decision records (`docs/adr/`)

| ADR | Topic |
|-----|--------|
| [001-transit-gateway.md](docs/adr/001-transit-gateway.md) | Transit Gateway (DESIGN-ONLY) |
| [002-direct-connect.md](docs/adr/002-direct-connect.md) | Direct Connect (DESIGN-ONLY) |
| [003-privatelink.md](docs/adr/003-privatelink.md) | PrivateLink (DESIGN-ONLY) |
| [004-aws-pcs.md](docs/adr/004-aws-pcs.md) | AWS PCS (DESIGN-ONLY) |
| [005-aws-res.md](docs/adr/005-aws-res.md) | AWS RES (DESIGN-ONLY) |
| [006-efa-networking.md](docs/adr/006-efa-networking.md) | EFA networking (DESIGN-ONLY) |
| [007-oidc-deploy-pipeline.md](docs/adr/007-oidc-deploy-pipeline.md) | OIDC deploy pipeline (DESIGN-ONLY) |

### Runbooks (`runbooks/`)

| Runbook | Trigger |
|---------|---------|
| [controller-restart.md](runbooks/controller-restart.md) | Controller recovery |
| [node-down.md](runbooks/node-down.md) | Node DOWN / unreachable |
| [node-drain-reboot.md](runbooks/node-drain-reboot.md) | Drain, reboot, rejoin |
| [failed-job.md](runbooks/failed-job.md) | Failed job triage |
| [stuck-job.md](runbooks/stuck-job.md) | Stuck / non-completing jobs |
| [connectivity-triage.md](runbooks/connectivity-triage.md) | Network / DNS / SG issues |
| [patch-static-nodes.md](runbooks/patch-static-nodes.md) | Patch Manager window |
| [slurm-bootstrap-rebuild.md](runbooks/slurm-bootstrap-rebuild.md) | Controller/bootstrap rebuild |
| [slurm-upgrade-rollback.md](runbooks/slurm-upgrade-rollback.md) | Slurm version upgrade / rollback |

### Incidents

| Path | Description |
|------|-------------|
| [incidents/templates/pir.md](incidents/templates/pir.md) | Blameless post-incident review template |

### Tests & evidence screenshots

| Path | Description |
|------|-------------|
| [tests/scheduler/test_smoke.sh](tests/scheduler/test_smoke.sh) | Scheduler smoke (submit / complete / cancel / cold-start) |
| [tests/scheduler/](tests/scheduler/) | Session screenshots (EC2, EFS, RDS, controller, login, portal, Grafana, alarms, `sacct`) |
| [tests/](tests/) | pytest unit/integration (bootstrap, image builder, policy, power-save, hpcops) |

---

## Repository map

```
.
├── .kiro/
│   ├── specs/hpc-platform-ops/   # requirements, design, tasks
│   └── steering/                 # product, tech, structure, sandbox constraints
├── automation/
│   ├── python/                   # hpcops, resume/suspend, portal, controller_setup
│   ├── lambda/                   # inspector ticket, etc.
│   ├── canaries/                 # debug / std canary scripts
│   └── cloud-init/               # node cloud-init templates
├── config/                       # slurm, users, prometheus, grafana
├── docs/                         # ops docs, ADRs, e2e, reports
├── incidents/templates/          # PIR template
├── runbooks/                     # operational runbooks
├── scripts/                      # deploy, preflight, ami_build, evidence, …
├── terraform/                    # root stack + modules (network, storage, controller, …)
├── tests/                        # pytest + scheduler smoke + screenshots
├── Makefile
└── README.md                     # this file
```

| Area | Path |
|------|------|
| Terraform root + modules | [`terraform/`](terraform/) |
| Deploy orchestration | [`scripts/deploy.py`](scripts/deploy.py) |
| AMI build / promote | [`scripts/ami_build.py`](scripts/ami_build.py), [`scripts/image_promote.py`](scripts/image_promote.py) |
| Preflight / policy | [`scripts/preflight.py`](scripts/preflight.py), [`scripts/policy_check.py`](scripts/policy_check.py) |
| CI | [`.github/workflows/ci.yml`](.github/workflows/ci.yml) |

---

## Reproduce

1. Clone repo; Python 3.12 + Terraform ≥ 1.0 + AWS credentials in sandbox.
2. `pip install -r requirements.txt`
3. SSM parameter `/hpc-testbed/ami/compute/current` is auto-seeded from the latest AL2023 AMI on first foundation apply (prefer promoting an Image Builder AMI that already contains Slurm under `/opt/slurm`).
4. `make preflight` then phased deploy:

   ```bash
   make foundation
   make ami-build
   make instances
   make full
   ```

5. Wait for controller bootstrap (first boot can take 15–25 min while Slurm is compiled and published to EFS `/shared/software/slurm`). Tail `/var/log/controller-init.log` via SSM if needed.
6. From login node: run [`tests/scheduler/test_smoke.sh`](tests/scheduler/test_smoke.sh) (`sinfo` / `sbatch` after shared EFS build appears).
7. Follow the checklist in [docs/e2e-test.md](docs/e2e-test.md); `make evidence` and inspect `evidence/session_*`.

---

## Sandbox constraints

Instance types limited to t2/t3/t3a/t4g micro–medium. Max **9** instances. Regions **us-east-1** / **us-west-2** only. Spot, large families, and EFA are unavailable by design.

See [docs/instance-budget.md](docs/instance-budget.md) and [`.kiro/steering/sandbox-constraints.md`](.kiro/steering/sandbox-constraints.md).

---

## Repository

**GitHub:** https://github.com/eyespan/aws-slurm-testbed

This repository contains the full implementation of a sandbox-scale HPC operations test bed: Terraform modules, Image Builder pipeline, Slurm controller/login/compute bootstrap, power-save resume/suspend, monitoring and portal, runbooks, ADRs, evidence tooling, and end-to-end validation artefacts.

| Area | Contents |
|------|----------|
| Specs & design | [`.kiro/specs/hpc-platform-ops/`](.kiro/specs/hpc-platform-ops/) — requirements, architecture diagram, task breakdown |
| Steering | [`.kiro/steering/`](.kiro/steering/) — product, tech, structure, sandbox constraints |
| Infrastructure | [`terraform/`](terraform/) — VPC, storage, controller, login, monitoring, portal, FIS, identity |
| Automation | [`automation/`](automation/) — resume/suspend, hpcops CLI, portal app, canaries, cloud-init |
| Deploy scripts | [`scripts/`](scripts/) — `deploy.py`, `ami_build.py`, preflight, evidence, policy checks |
| Operations docs | [`docs/`](docs/) — e2e guide, ops runbooks index, ADRs, alert tuning, incident lifecycle |
| Runbooks | [`runbooks/`](runbooks/) — controller restart, node drain, failed/stuck jobs, connectivity, patch |
| Tests & screenshots | [`tests/`](tests/) — pytest; [`tests/scheduler/`](tests/scheduler/) smoke script and session evidence images |
| CI | [`.github/workflows/ci.yml`](.github/workflows/ci.yml) — static gates on pull request |

The project is intentionally scoped to sandbox limits so it can be stood up, exercised, evidenced, and torn down in a single short session.

---

## Credits & attribution

**HPC Platform Operations Test Bed** (`aws-slurm-testbed`) is an independent engineering project designed, developed, and maintained by **Yohannes Measho**.

The project demonstrates production-oriented HPC platform operations on AWS, including:

- Self-managed Slurm on EC2 (controller, login, static debug, cloud power-save)
- Terraform infrastructure as code under sandbox instance and region constraints
- Amazon EFS shared storage and optional FSx for Lustre (TRY)
- Image Builder AMI lifecycle with SSM parameter promotion and rollback
- Slurm accounting via slurmdbd and MariaDB (RDS)
- Status portal (ALB) and Prometheus/Grafana observability
- CloudWatch SLI alarms tagged with severity, SLI, and runbook
- Operational tooling (`hpcops`: drain, diagnose, requeue)
- Runbooks, incident lifecycle, and blameless PIR template
- Audit evidence collection and service reporting
- Fault injection (FIS) templates where the sandbox allows

### Author

**Yohannes Measho**

Cloud / DevOps / Platform Engineer

GitHub: [https://github.com/eyespan](https://github.com/eyespan)

Project: [https://github.com/eyespan/aws-slurm-testbed](https://github.com/eyespan/aws-slurm-testbed)

---

## Open source & third-party technologies

This project makes use of open-source technologies and third-party services, including but not limited to:

- [Slurm Workload Manager](https://slurm.schedmd.com/)
- Terraform
- Amazon Linux 2023
- Prometheus
- Grafana
- MUNGE
- MariaDB
- Python (boto3, FastAPI/Flask-style portal)
- GitHub Actions
- AWS SDKs

Each third-party project remains subject to its own licence and terms of use.

---

## AWS services

The test bed is designed to run on Amazon Web Services and uses services including, where enabled:

- Amazon EC2, VPC, NAT Gateway, Elastic Load Balancing
- Amazon EFS (and optionally Amazon FSx for Lustre)
- Amazon RDS (MariaDB)
- EC2 Image Builder, Systems Manager (Parameter Store, Session Manager, Patch Manager)
- Amazon CloudWatch, CloudTrail, Config, GuardDuty, Security Hub
- AWS KMS, Secrets Manager
- AWS Fault Injection Simulator (where not blocked by SCP)
- IAM, Route 53 private hosted zones

AWS services are subject to the applicable AWS Customer Agreement, service terms, and pricing. Sandbox accounts may further restrict which services and instance types are available.

---

## Licence

Copyright © 2026 Eyespan Limited

Unless otherwise stated, the original source code and documentation in this repository are made available under the **MIT License**.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files, to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software, subject to the conditions of the MIT License.

The software is provided **"as is"**, without warranty of any kind, express or implied.

See the [`LICENSE`](LICENSE) file for the complete licence text.

### Third-party licences

The MIT License applies only to original project material covered by this repository's licence.

Third-party libraries, frameworks, schedulers (including SchedMD Slurm), documentation, and cloud services remain subject to their respective licences and terms.

Users of this project are responsible for reviewing and complying with those licences and terms.

---

## Disclaimer

This project is provided for educational, demonstration, research, and engineering portfolio purposes.

No guarantee is made regarding:

- production suitability for real HPC workloads
- security or compliance in a shared or regulated environment
- availability, performance, or scalability beyond the sandbox design
- AWS costs or service quotas
- behaviour of optional TRY paths (FSx, Simple AD, NICE DCV, FIS) when blocked by policy

Always review and adapt the implementation to the requirements of your own environment before deploying it outside a disposable sandbox.

The repository is a **working reference implementation** of HPC platform operations practices under constrained AWS sandbox rules—not a commercial product or a turnkey production cluster.
