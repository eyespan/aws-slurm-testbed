# ADR 006: Elastic Fabric Adapter (DESIGN-ONLY)

## Status
DESIGN-ONLY.

## Context
EFA enables low-latency MPI for tightly coupled HPC.

## Decision (target)
Use EFA-enabled instance families and placement groups for MPI partitions.

## Why not built
EFA instance families and placement constraints exceed sandbox instance allow-list and budget.

## Sandbox substitute
Ethernet-only t3 family nodes; document MPI-over-TCP as unsupported for performance tests.
