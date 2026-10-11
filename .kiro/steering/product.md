---
inclusion: always
---

# Product: HPC platform test bed

## Purpose
A scaled-down, reproducible test bed that demonstrates how to **operate an AWS-based HPC platform as a product** for a regulated-sector customer. The workloads support safety-significant analysis, so availability, integrity and auditability matter more than raw performance.

The production target uses AWS PCS (managed Slurm) and AWS RES. Neither is available in the sandbox. This test bed uses self-managed Slurm on small EC2 instances to demonstrate the same operating practices: reliability, automation, observability, patching, security evidence and incident management.

## Audience
Hiring managers and technical interviewers reviewing the repo, and the author as a working reference for runbooks and IaC patterns.

## Principles
- **Operate, don't just build:** every component has an SLI, an alert, a runbook and a failure experiment.
- **Auditable by default:** changes go through CI, actions leave evidence, runbooks are repeatable.
- **Blameless:** post-incident reviews focus on system causes and tracked corrective actions.
- **Honest scope:** each requirement is tagged BUILD, SIMULATE, TRY or DESIGN-ONLY. Never overstate what is running.

## Out of scope
Real scientific workloads, real customer data, production-scale performance, anything requiring services listed as unavailable in `sandbox-constraints.md`.
