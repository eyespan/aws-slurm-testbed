---
inclusion: always
---

# Repository structure

```
hpc-testbed/
├── .kiro/
│   ├── steering/                 # sandbox-constraints, product, tech, structure
│   ├── specs/hpc-platform-ops/   # requirements.md, then design.md and tasks.md
│   └── hooks/                    # fmt/lint on save, runbook link check
├── terraform/
│   ├── bootstrap/                # state/session setup, tagging, KMS, CloudTrail
│   ├── modules/
│   │   ├── network/              # VPC, subnets, SGs, Route 53 private zone
│   │   ├── slurm-controller/     # head node, slurmdbd, config templates
│   │   ├── slurm-compute/        # launch template, power-save scripts, IAM
│   │   ├── login-portal/         # login node, ALB, status portal, optional DCV
│   │   ├── storage/              # EFS baseline, optional FSx for Lustre
│   │   ├── identity/             # Simple AD / LDAP, SSSD config
│   │   ├── observability/        # CloudWatch alarms/dashboards, Prometheus/Grafana
│   │   ├── image-pipeline/       # Image Builder, patch baselines
│   │   ├── security-audit/       # Config rules, GuardDuty, Security Hub
│   │   └── fis-experiments/      # fault injection templates
│   └── envs/sandbox/             # root module wiring everything together
├── ansible-or-scripts/           # node bootstrap (cloud-init, Slurm install)
├── automation/
│   ├── python/                   # drain/reboot tooling, evidence collector, reports
│   └── shell/                    # make targets, health checks
├── runbooks/                     # one file per alert or procedure
├── incidents/
│   ├── templates/                # post-incident review template
│   └── reviews/                  # completed reviews with tracked actions
├── docs/
│   ├── adr/                      # decisions, including DESIGN-ONLY items
│   ├── architecture/             # diagrams
│   ├── instance-budget.md
│   ├── sandbox-notes.md          # what worked, what was blocked
│   └── service-reports/          # generated monthly-style reports
├── evidence/                     # exported audit and test evidence per session
├── tests/                        # pytest, terraform tests, scheduler smoke tests
├── .github/workflows/            # lint, plan, apply, drift
├── Makefile                      # up, down, test, evidence
└── README.md
```

Place code in the folder named above. Create new folders only with a reason recorded in an ADR.
