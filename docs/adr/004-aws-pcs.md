# ADR 004: AWS Parallel Computing Service (DESIGN-ONLY)

## Status
DESIGN-ONLY — not built in this sandbox.

## Context
AWS PCS provides managed Slurm controllers and integration with EC2 capacity providers.

## Decision (target production)
Use AWS PCS for managed controller HA, capacity providers, and reduced undifferentiated ops.

## Why not built here
Sandbox budget, account limits, and the learning goal of operating self-managed Slurm.

## Sandbox substitute
Self-managed controller + `slurm_resume.py` / `slurm_suspend.py` + launch template + private DNS.
