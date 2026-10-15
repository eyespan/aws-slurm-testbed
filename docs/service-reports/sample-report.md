# Service report — sample (committed)

Period: last 30 days (illustrative sample; regenerate with `python scripts/service_report.py`)

## Availability
- Scheduler: n/a until live metrics exist (SLO 99.5%)
- Login/portal: n/a until ALB + probe deployed (SLO 99.5%)

## Latency
- Warm canary (debug): target p95 < 30 s
- Cold canary (std, includes resume): target p95 < 6 min

## Capacity
- Budget cap: 9 instances (includes Image Builder reserve of 2)
- Typical steady state: controller + login + monitoring + debug = 4; std bursts up to +3

## Incidents
- None in sample pack. Use `incidents/reviews/` after SANDBOX exercises.

## Limitations
- Billing and Cost Explorer data are not available in this sandbox account model.
- Utilisation anomalies rely on CloudWatch custom metrics populated after go-live.
