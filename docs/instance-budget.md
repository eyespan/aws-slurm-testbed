# Instance Budget

This document describes the instance budget for the HPC Platform Operations Test Bed sandbox environment.

## Budget Overview

The sandbox environment has a maximum instance capacity of **9 instances** across all roles. This includes both running and stopped instances.

| Role | Type | Count | Notes |
|---|---|---|---|
| Controller | t3.medium | 1 | slurmctld, slurmdbd, MariaDB |
| Login | t3.small | 1 | Job submission, optional NICE DCV (TRY: may need t3.medium) |
| Monitoring | t3.medium | 1 | Prometheus, Grafana, Slurm exporter |
| `debug` node | t3.micro | 1 | Static and always on, so canaries never wait on a power-up |
| `std` nodes | t3.small | up to 3 | Cloud nodes, power-saved |
| **Total running** | | **7** | |
| Image Builder reserve | | 2 | Build and test instances count toward the cap |
| **Cap** | | **9** | Stopped instances also count |

## Lambda Budget

The sandbox also has a Lambda function limit of 10. We target **6 or fewer** functions:

| Function | Purpose |
|---|---|
| Probe Lambda | Health checks for slurmctld and portal endpoint |
| Service Report Lambda | Generate monthly service reports |
| Image Promote Lambda | Promote new AMIs after testing |
| Inspector Ticket Lambda | Create tickets for security findings |
| Resume Helper Lambda | Optional: assist with node resume |
| PIR Summariser Lambda | Optional: auto-generate PIR summaries |

## Usage Guidelines

### Instance Allocation

1. **Always-on instances** (controller, login, monitoring, debug): These are static and count toward the budget continuously
2. **Cloud compute nodes** (`std` partition): These are power-saved and only count when running
3. **Image Builder instances**: 2 reserved slots for building and testing new AMIs

### Preflight Check

Before running `make up`, the preflight script verifies:

- Current instance count is within budget
- Region is allowed (`us-east-1` or `us-west-2`)
- All instance types are from the allowed list (t2/micro/small/medium, t3/micro/small/medium, t3a/micro/small/medium, t4g/micro/small/medium)
- No references to unavailable services

### What Happens if Budget is Exceeded

- CI pipeline blocks the plan
- Preflight script blocks apply
- Resume program refuses to launch additional nodes

## Tracking Instance Usage

To check current instance usage:

```bash
# Count running instances
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running,pending" "Name=tag:Project,Values=hpc-testbed" --query 'Reservations[].Instances[].InstanceId' --output text | wc -w

# Count stopped instances
aws ec2 describe-instances --filters "Name=instance-state-name,Values=stopped,stopping" "Name=tag:Project,Values=hpc-testbed" --query 'Reservations[].Instances[].InstanceId' --output text | wc -w
```

## Sandbox Limitations

The following services are **unavailable** or have **limited functionality** in the sandbox:

| Service | Status | Notes |
|---|---|---|
| AWS ParallelCluster | DESIGN-ONLY | Use self-managed Slurm instead |
| AWS Resource Scheduler | DESIGN-ONLY | See ADR for RES |
| Transit Gateway | DESIGN-ONLY | See ADR for Transit Gateway |
| Direct Connect | DESIGN-ONLY | See ADR for Direct Connect |
| PrivateLink | DESIGN-ONLY | Only gateway endpoints allowed |
| EFA networking | UNAVAILABLE | Not supported in sandbox |
| FSx for Lustre | TRY (may fail) | May be blocked or unaffordable |
| NICE DCV | TRY (may fail) | May require additional licensing |

All limitations are documented in the design and runbooks.

## References

- Design: Section 3.1 "Instance and resource budget"
- Requirements: Section 1.1-1.4 "Sandbox compliance guardrails"
- Tasks: Task 2 "Implement sandbox guardrails"
