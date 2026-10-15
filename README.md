# HPC Platform Operations Test Bed

Scaled-down Slurm on AWS EC2 demonstrating production HPC operations practices: SLIs/alerts, runbooks, image/patch lifecycle, audit evidence, fault injection, and service reporting.

Built for a Pluralsight-style AWS sandbox (instance cap 9, region allow-list, no TGW/PrivateLink/PCS).

## Architecture (built)

| Layer | What |
|---|---|
| Network | VPC, 2 AZ public/private subnets, NAT, SGs, R53 `hpc.internal`, flow logs |
| Storage | Encrypted EFS `/shared` + `/home`; optional FSx Lustre (TRY) |
| Scheduler | Self-managed Slurm controller + slurmdbd; partitions `debug` (static) and `std` (cloud power-save) |
| Access | Login node (SSH + status portal), YAML local users (AD optional) |
| Elasticity | `slurm_resume.py` / `slurm_suspend.py` + launch template + SSM AMI pointer |
| Observability | Monitoring node (Prometheus/Grafana), CloudWatch alarms (tagged severity/sli/runbook), probe Lambda, canaries |
| Lifecycle | Image Builder components, `image_promote` / `ami-rollback`, Patch Manager window |
| Security | KMS, CloudTrail, Config rules, GuardDuty, Security Hub, `make evidence` |
| Resilience | FIS templates (node stop, controller stop, DNS failure SSM doc), incident/PIR process |

## Built vs simulated vs design-only

| Capability | Status |
|---|---|
| Self-managed Slurm + power-save | **Built** |
| EFS shared storage | **Built** |
| FSx Lustre | **TRY** (`make fsx-up`) |
| Simple AD | **TRY** (`enable_directory=true`) |
| AWS PCS | **DESIGN-ONLY** (ADR 004) |
| AWS RES | **DESIGN-ONLY** (ADR 005) |
| EFA networking | **DESIGN-ONLY** (ADR 006) |
| OIDC deploy pipeline | **DESIGN-ONLY** (ADR 007) |
| Transit Gateway / DX / PrivateLink | **DESIGN-ONLY** (ADRs 001–003) |

## Quick start

```bash
# Quality gates (no AWS required)
make lint test

# Live sandbox session
make preflight
make up                 # creates network/storage/pipeline (does NOT build AMI)
make ami-build          # start Image Builder, wait, promote AMI to SSM (45–90 min)
make up                 # re-apply so controller/login/debug launch from HPC AMI
# ... smoke tests, canaries, ops runbooks ...
make evidence
make down
```

> **Important:** The Image Builder *pipeline* is only *scheduled* (Sunday 02:00 UTC).  
> `terraform apply` does **not** execute it. Use `make ami-build` (or set `TF_VAR_build_ami_on_apply=true`) before relying on Slurm on the nodes.

### Key make targets

| Target | Purpose |
|---|---|
| `preflight` | Identity, region, capacity vs budget |
| `plan` / `apply` / `drift` | Terraform (apply needs `CONFIRM=yes`) |
| `ami-build` | Run Image Builder pipeline now, wait, promote AMI to SSM |
| `evidence` | Audit pack with SHA-256 manifest |
| `ami-promote` / `ami-rollback` | SSM AMI current/previous |
| `service-report` | Monthly-style availability/capacity report |
| `fsx-up` / `fsx-down` | Optional scratch filesystem |

## Ops CLI

```bash
python -m hpcops drain-node debug-1 --reason "maintenance"   # dry-run default
python -m hpcops drain-node debug-1 --reason "maintenance" --yes
python -m hpcops diagnose-job 12345
python -m hpcops diagnose-node std-1
python -m hpcops requeue-stuck --minutes 30
```

## Sample artefacts

- Sample service report: `docs/service-reports/sample-report.md`
- PIR template: `incidents/templates/pir.md`
- Runbooks: `runbooks/`
- Alert tuning log: `docs/alert-tuning.md`
- Sandbox TRY outcomes: `docs/sandbox-notes.md`

## Reproduce

1. Clone repo; Python 3.12 + Terraform ≥ 1.0 + AWS credentials in sandbox.
2. `pip install -r requirements.txt`
3. SSM parameter `/hpc-testbed/ami/compute/current` is auto-seeded from the latest AL2023 AMI on first apply (optional: promote an Image Builder AMI that already contains Slurm under `/opt/slurm`).
4. `make preflight up`
5. Wait for controller bootstrap (first boot can take 15–25 min while Slurm is compiled and published to EFS `/shared/software/slurm`). Tail `/var/log/controller-init.log` via SSM if needed.
6. From login node: run `tests/scheduler/test_smoke.sh` (`sinfo`/`sbatch` become available after the shared EFS build appears).
7. `make evidence` and inspect `evidence/session_*`

## Credits / constraints

Instance types limited to t2/t3/t3a/t4g micro–medium. Max 9 instances. Regions us-east-1 / us-west-2 only. Spot, large families, and EFA are unavailable by design.
