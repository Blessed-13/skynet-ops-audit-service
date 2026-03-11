# Observability — skynet-ops-audit-service

> This document covers logging, metrics, and alerting for the skynet-ops-audit-service
> running on AWS ECS Fargate with CloudWatch.

---

## Logging

### Approach
The service emits **structured JSON logs** on stdout.
Every log line is a valid JSON object — easy to filter, parse, and query in CloudWatch.

### Log Driver
ECS ships logs directly to CloudWatch via the `awslogs` log driver.
No log agent or sidecar required.

```hcl
logConfiguration = {
  logDriver = "awslogs"
  options = {
    "awslogs-group"         = "/ecs/skynet-ops-audit-service"
    "awslogs-region"        = "ap-south-1"
    "awslogs-stream-prefix" = "ecs"
  }
}
```

### Log Format
Every request produces a structured log line:

```json
{
  "timestamp": "2026-03-09T18:00:00.000Z",
  "level": "info",
  "service": "skynet-ops-audit-service",
  "env": "dev",
  "message": "request",
  "method": "POST",
  "path": "/events",
  "status": 201,
  "duration_ms": 12.4
}
```

Event stored log:
```json
{
  "timestamp": "2026-03-09T18:00:00.000Z",
  "level": "info",
  "service": "skynet-ops-audit-service",
  "env": "dev",
  "message": "event_stored",
  "eventId": "evt_a1b2c3d4",
  "type": "roster_update",
  "tenantId": "academy_001",
  "severity": "info"
}
```

Error log:
```json
{
  "timestamp": "2026-03-09T18:00:00.000Z",
  "level": "error",
  "service": "skynet-ops-audit-service",
  "env": "dev",
  "message": "metrics_demo_error_triggered"
}
```

### Log Levels

| Level     | When used                                      |
|-----------|------------------------------------------------|
| `info`    | Every request, every event stored, startup     |
| `error`   | Simulated errors, unhandled exceptions         |

Log level is configurable via `LOG_LEVEL` env var — set to `warning` in production to reduce volume and cost.

### Log Retention
- **Dev/Pilot:** 7 days — sufficient for debugging, keeps costs low
- CloudWatch default is never-expire — we explicitly override this

### Viewing Logs

```bash
# Live tail
aws logs tail /ecs/skynet-ops-audit-service --follow --region ap-south-1

# Filter errors only
aws logs filter-log-events \
  --log-group-name /ecs/skynet-ops-audit-service \
  --filter-pattern "ERROR" \
  --region ap-south-1

# Filter slow requests (duration > 500ms)
aws logs filter-log-events \
  --log-group-name /ecs/skynet-ops-audit-service \
  --filter-pattern '{ $.duration_ms > 500 }' \
  --region ap-south-1

# Filter by tenant
aws logs filter-log-events \
  --log-group-name /ecs/skynet-ops-audit-service \
  --filter-pattern '{ $.tenantId = "academy_001" }' \
  --region ap-south-1
```

---

## Metrics

All metrics come from the **AWS ALB** and **ECS** automatically — no custom metric instrumentation needed at pilot scale.

| Metric                        | Source       | What it tells you                        |
|-------------------------------|--------------|------------------------------------------|
| `TargetResponseTime`          | ALB          | Average response latency per request     |
| `HTTPCode_Target_5XX_Count`   | ALB          | Number of 5xx errors from the service    |
| `HTTPCode_Target_4XX_Count`   | ALB          | Number of 4xx errors (bad requests)      |
| `RequestCount`                | ALB          | Total traffic volume                     |
| `UnHealthyHostCount`          | ALB          | Number of unhealthy ECS tasks            |
| `CPUUtilization`              | ECS          | Container CPU usage                      |
| `MemoryUtilization`           | ECS          | Container memory usage                   |

### Viewing Metrics in AWS Console
- Go to **CloudWatch → Metrics → AWS/ApplicationELB**
- Filter by your ALB name: `skynet-ops-audit-service-alb`

---

## Alerts

Three CloudWatch alarms are configured via Terraform:

### Alert 1 — High Error Rate
```
Metric:     HTTPCode_Target_5XX_Count
Threshold:  > 5 errors in 1 minute
Periods:    2 consecutive evaluation periods
Rationale:  At pilot scale (5,000-20,000 req/day), 5 errors/minute
            indicates a real service problem, not noise
Action:     Check logs, consider force redeployment (see runbook)
```

### Alert 2 — High Latency
```
Metric:     TargetResponseTime (average)
Threshold:  > 1 second average
Periods:    2 consecutive evaluation periods
Rationale:  Targets are POST /events < 500ms, GET /events < 1000ms
            Average > 1s means something is wrong (EFS, CPU, DB)
Action:     Check EFS performance, CPU metrics, restart task
```

### Alert 3 — Unhealthy Hosts
```
Metric:     UnHealthyHostCount
Threshold:  > 0
Periods:    1 evaluation period
Rationale:  Single task deployment — any unhealthy host = service degraded
            treat_missing_data = "breaching" so missing health = alarm
Action:     Immediate — check task status, force redeploy
```

---

## Observability Testing with /metrics-demo

The `/metrics-demo` endpoint exists specifically to generate observable signals:

```bash
# Trigger a 500 error — should appear in error rate alarm
curl "http://localhost:8000/metrics-demo?mode=error"

# Trigger slow response — should appear in latency metrics
curl "http://localhost:8000/metrics-demo?mode=slow"

# Trigger burst logs — visible in CloudWatch log stream
curl "http://localhost:8000/metrics-demo?mode=burst"
```

Use these to verify alarms fire correctly after deployment.

---

## Latency Targets

| Endpoint         | Target      | Alert Threshold |
|------------------|-------------|-----------------|
| `GET /health`    | < 200ms     | N/A             |
| `POST /events`   | < 500ms     | > 1s average    |
| `GET /events`    | < 1000ms    | > 1s average    |
| `GET /metrics-demo?mode=slow` | ~2s (intentional) | excluded from alerts |
