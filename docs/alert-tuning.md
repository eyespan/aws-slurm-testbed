# Alert tuning log

Record each threshold change after Task 23 (observability go-live).

| Date | Alarm | Old threshold | New threshold | Noise removed / reason |
|---|---|---|---|---|
| | | | | |

Initial defaults (from Terraform observability module):
- Scheduler availability: Minimum HealthCheckStatus < 1 for 3 periods of 60s
- Resume failures: Sum > 0 over 5 minutes
- Warm latency: Maximum canary_job_start_seconds > 30s (debug)
- Cold latency: Maximum canary_job_start_seconds > 360s (std)
- EFS burst credits: Average < 100 GiB remaining
