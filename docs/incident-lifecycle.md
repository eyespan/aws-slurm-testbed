# Incident lifecycle

## Severity matrix

| Severity | Description | Response target | Example |
|---|---|---|---|
| SEV-1 | Cluster unusable for all users | 15 min ack | Controller down, EFS unavailable |
| SEV-2 | Major degradation | 30 min ack | Login node down, resume failures across std |
| SEV-3 | Partial impact | Next business day | Single node DOWN, canary flake |
| SEV-4 | Cosmetic / no user impact | Backlog | Dashboard gap, doc typo |

## Stages
1. **Detect** — alert, canary, or user report
2. **Triage** — severity, commander, communication channel
3. **Mitigate** — restore service using runbooks
4. **Resolve** — root cause addressed or workaround accepted
5. **Review** — blameless PIR within 5 business days
6. **Track** — corrective actions with owners and due dates

## Communication templates
- **Ack:** "We are aware of <symptom>. Severity <N>. Updates every 30 min."
- **Mitigate:** "Mitigation applied: <action>. Monitoring recovery."
- **Resolve:** "Service restored at <time>. PIR will follow."
