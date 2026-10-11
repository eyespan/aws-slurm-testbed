# Requirements: HPC Platform Operations Test Bed

## Introduction

This test bed demonstrates the operation of a production AWS HPC platform for a regulated-sector customer, scaled down to run in a Pluralsight AWS sandbox. It reproduces the operating practices of the role (reliability, automation, observability, patching, security evidence, incident management and service reporting) using self-managed Slurm on small EC2 instances.

Each requirement is tagged:

- **BUILD:** implemented and demonstrated in the sandbox.
- **SIMULATE:** implemented at reduced fidelity, with the gap documented.
- **TRY:** attempt in the sandbox. If blocked, fall back as stated and record the outcome in `docs/sandbox-notes.md`.
- **DESIGN-ONLY:** documented in an ADR and diagram. Not deployable in the sandbox.

## Glossary

- **Platform:** the Slurm cluster, its AWS infrastructure, and the user-facing login and portal services.
- **Controller:** the head node running `slurmctld` and `slurmdbd`.
- **Compute node:** a power-saved EC2 instance launched on demand for Slurm jobs.
- **SLI:** a measured service indicator. **SLO:** its target.
- **PIR:** post-incident review.
- **Evidence pack:** an exported set of configuration, logs and reports supporting an audit or accreditation claim.

---

## Requirement 1: Sandbox compliance guardrails [BUILD]

**User story:** As the platform engineer, I want the code to enforce the sandbox limits, so that no deployment is blocked or flagged for misuse.

#### Acceptance criteria
1. WHEN a Terraform plan contains an EC2 instance type outside t2/t3/t3a/t4g micro, small or medium THEN the validation SHALL fail the plan.
2. WHEN a configured region is not us-east-1 or us-west-2 THEN the validation SHALL fail the plan.
3. WHEN the planned instance count, including the Image Builder reserve, exceeds 9 THEN the CI check SHALL fail.
4. WHEN a module references a service listed as unavailable THEN the policy check SHALL fail and point to the relevant ADR.

## Requirement 2: Reproducible environment lifecycle [BUILD]

**User story:** As the platform engineer, I want to rebuild and tear down the whole environment from code, so that an expired sandbox costs me no work.

#### Acceptance criteria
1. WHEN `make up` is run with valid credentials THEN the system SHALL create the full environment without manual console steps.
2. WHEN `make down` is run THEN the system SHALL export evidence to `evidence/` and destroy all tagged resources.
3. THE system SHALL tag every resource with Project, Env and Session.
4. WHEN a session starts THEN a preflight script SHALL verify identity, region and remaining capacity against the instance budget.

## Requirement 3: Network foundation [BUILD]

**User story:** As the platform engineer, I want a segmented, diagnosable network, so that connectivity and DNS problems can be traced end to end.

#### Acceptance criteria
1. THE system SHALL provide a VPC with public and private subnets across at least two Availability Zones, security groups per tier, and a Route 53 private hosted zone.
2. THE system SHALL NOT use interface VPC endpoints, Transit Gateway or PrivateLink.
3. WHEN a connectivity check fails THEN the diagnostic runbook SHALL cover security groups, routing, NACLs, DNS and flow logs in a repeatable order.
4. THE `docs/adr/` folder SHALL contain DESIGN-ONLY ADRs for Transit Gateway, Direct Connect and PrivateLink, describing how the target platform would use them.

## Requirement 4: Slurm scheduler service [BUILD]

**User story:** As a user, I want a working scheduler with accounting, so that I can submit and track jobs.

#### Acceptance criteria
1. THE Controller SHALL run `slurmctld` and `slurmdbd` with accounting enabled, configured from templates in version control.
2. THE system SHALL provide a login node from which users submit jobs.
3. WHEN the Controller restarts THEN the scheduler SHALL recover queued jobs and the health check SHALL confirm it.
4. THE Slurm version SHALL be pinned in one variable, and an upgrade runbook SHALL describe planning, execution and rollback.
5. THE ADR for PCS SHALL record how this self-managed design differs from AWS PCS (DESIGN-ONLY).

## Requirement 5: Elastic compute queues [SIMULATE]

**User story:** As the platform engineer, I want compute capacity that scales with demand within sandbox limits, so that I can tune autoscaling behaviour.

#### Acceptance criteria
1. WHEN jobs are pending THEN Slurm power saving SHALL launch compute nodes up to a configured maximum no greater than the budget.
2. WHEN nodes are idle beyond the configured suspend time THEN the system SHALL terminate them.
3. WHEN an EC2 launch fails THEN the node SHALL be marked down with a reason and an alarm SHALL fire.
4. THE system SHALL record node resume latency so that job start latency can be measured.
5. THE docs SHALL state that Spot, large instance families and EFA are unavailable.

## Requirement 6: Shared storage [TRY]

**User story:** As a user, I want shared storage for job data, so that jobs on any node see the same files.

#### Acceptance criteria
1. THE system SHALL mount EFS as the baseline shared filesystem on all nodes.
2. WHEN the sandbox permits THEN the system SHALL deploy a short-lived FSx for Lustre filesystem and run a throughput check against it.
3. IF FSx for Lustre is blocked or unaffordable THEN the system SHALL fall back to EFS and record the result in `docs/sandbox-notes.md`.
4. WHEN storage throughput or free space crosses a threshold THEN an alarm SHALL fire with a linked runbook.

## Requirement 7: Scheduler operations tooling [BUILD]

**User story:** As the on-call engineer, I want tested procedures for scheduler, node and job failures, so that I can diagnose under time pressure.

#### Acceptance criteria
1. THE system SHALL include scripts and runbooks for stuck jobs, failed jobs, and nodes in drain, down or fail states.
2. WHEN a node is drained for maintenance THEN the tooling SHALL wait for running jobs, apply the action, reboot and return the node to service, logging each step.
3. WHEN a destructive action is requested THEN the tooling SHALL require an explicit confirmation flag.
4. THE tests SHALL include scheduler smoke tests covering submit, run, complete and cancel.

## Requirement 8: Observability and alert quality [BUILD]

**User story:** As the on-call engineer, I want actionable, low-noise alerts, so that I can respond to real problems.

#### Acceptance criteria
1. THE system SHALL collect scheduler, node, storage and endpoint metrics in CloudWatch and Prometheus, with Grafana dashboards for queue wait time, job start latency, node states and storage throughput.
2. THE system SHALL probe slurmctld and the login/portal endpoint on a schedule and alarm on repeated failure.
3. WHEN an alert is defined THEN it SHALL include severity, an SLI reference and a runbook link, enforced by a CI check.
4. THE docs SHALL record each alert's tuning history to show noise reduction.

## Requirement 9: User access and portal [TRY]

**User story:** As a user, I want a login service and a status portal, so that I can access the platform and see its health.

#### Acceptance criteria
1. THE system SHALL provide a status portal behind an Elastic Load Balancer with health checks.
2. THE system SHALL authenticate users via Simple AD or Managed AD with LDAP and SSSD, where the sandbox permits.
3. WHEN the sandbox permits THEN the system SHALL install NICE DCV on a t3.medium instance. Otherwise it SHALL record the limitation.
4. THE docs SHALL record that AWS RES is DESIGN-ONLY and describe how it would fit.

## Requirement 10: Patching, vulnerability and image lifecycle [BUILD]

**User story:** As the platform engineer, I want a controlled image and patch lifecycle, so that fleets stay secure within agreed windows.

#### Acceptance criteria
1. THE system SHALL build hardened node images with EC2 Image Builder on a schedule and publish versioned AMIs.
2. WHEN Inspector reports a finding above a configured severity THEN the system SHALL raise a ticket-style record with a remediation deadline.
3. THE system SHALL apply patches via Systems Manager inside a defined maintenance window, with drain, patch, verify and rejoin steps.
4. WHEN a new AMI is promoted THEN the compute launch template SHALL reference it and the rollback to the previous AMI SHALL be documented and tested.

## Requirement 11: Security posture and audit integrity [BUILD]

**User story:** As the platform engineer, I want strong, evidenced controls, so that I can support customer compliance and accreditation activities.

#### Acceptance criteria
1. THE system SHALL use least-privilege IAM roles, KMS customer-managed keys for storage and logs, and no long-lived credentials in code.
2. THE system SHALL enable CloudTrail with log file validation and AWS Config recording with rules for encryption, public access and tagging.
3. WHEN `make evidence` is run THEN the system SHALL produce an evidence pack covering IAM, KMS, CloudTrail, Config and patch state, with timestamps and hashes.
4. WHEN a Config rule is non-compliant THEN the finding SHALL appear in the monthly service report.

## Requirement 12: Incident management and resilience testing [BUILD]

**User story:** As the incident lead, I want a rehearsed incident process, so that responses are repeatable and learning is tracked.

#### Acceptance criteria
1. THE repo SHALL include an incident lifecycle document covering triage, response, escalation, customer communication and closure.
2. WHEN a fault injection experiment runs THEN the experiment SHALL be defined as code, run within the 20-minute limit and linked to a hypothesis.
3. THE experiments SHALL include loss of a compute node, loss of an AZ's subnet access, and a DNS failure.
4. WHEN an incident or experiment completes THEN a blameless PIR SHALL be written from the template, with corrective actions tracked to closure.

## Requirement 13: Infrastructure CI/CD [BUILD]

**User story:** As the platform engineer, I want a safe pipeline for infrastructure change, so that every change is reviewed, tested and reversible.

#### Acceptance criteria
1. WHEN a pull request is opened THEN the pipeline SHALL run fmt, validate, tflint, checkov and unit tests, and post the Terraform plan.
2. WHEN a change is merged THEN the apply SHALL run with a manual approval gate.
3. THE pipeline SHALL run drift detection on a schedule and report differences.
4. THE docs SHALL describe a safe rollback for a failed apply.

## Requirement 14: Capacity, cost and service reporting [SIMULATE]

**User story:** As the service owner, I want regular service reports and capacity forecasts, so that I can meet SLAs and review the service monthly.

#### Acceptance criteria
1. THE system SHALL generate a report with availability, incidents, changes and capacity for a reporting period.
2. THE system SHALL compute SLA attainment from probe data against documented SLOs.
3. THE system SHALL forecast demand from queue and utilisation history.
4. WHERE billing data is unavailable THEN the system SHALL flag anomalies from utilisation and instance-hours instead, and the report SHALL state this limitation.

## Requirement 15: Runbooks [BUILD]

**User story:** As any on-call engineer, I want consistent runbooks, so that any response is repeatable and auditable.

#### Acceptance criteria
1. THE `runbooks/` folder SHALL contain one file per alert or procedure using a standard template (trigger, impact, diagnosis, action, verification, escalation, evidence).
2. WHEN a runbook is executed in a rehearsal THEN the result SHALL be logged in `incidents/` or `evidence/`.
3. THE CI SHALL fail when an alert has no runbook link or a runbook link is broken.

## Requirement 16: Design-only artefacts [DESIGN-ONLY]

**User story:** As a reviewer, I want to see how the sandbox differs from the production target, so that the scope is honest and the target design is clear.

#### Acceptance criteria
1. THE repo SHALL contain ADRs and diagrams for AWS PCS, AWS RES, EFA networking, Transit Gateway, Direct Connect and PrivateLink.
2. EACH ADR SHALL state what the target design is, why it is not built here, and what the sandbox substitute is.

---

## Traceability to the job description

| Job description area | Requirements |
|---|---|
| Scheduler availability, job start latency, queue wait | 4, 5, 8 |
| Incident lifecycle and PIRs | 12, 15 |
| Slurm troubleshooting, drain/reboot, upgrades | 4, 7 |
| Patching, vulnerability, AMI lifecycle | 10 |
| Capacity and cost | 5, 14 |
| Terraform/Python/shell automation, CI/CD, drift, rollback | 1, 2, 13 |
| Observability stack and alert quality | 8 |
| Resilience and failure mode testing | 12 |
| PCS, RES, EC2, FSx, S3, EFA | 5, 6, 9, 16 |
| Networking diagnosis | 3 |
| IAM, KMS, CloudTrail/Config, compliance evidence | 11 |
| SLA reporting and runbooks | 14, 15 |
| Desirable: containers, Spack, DCV, AD/LDAP | 6, 9 |
