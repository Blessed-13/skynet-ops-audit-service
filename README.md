# skynet-ops-audit-service

A lightweight operational audit event service built for the AIRMAN Skynet ecosystem.
Ingests and stores operational events (roster updates, dispatch approvals, schedule conflicts etc.)
and exposes them via a simple REST API.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Local Setup](#local-setup)
- [API Endpoints](#api-endpoints)
- [Environment Variables](#environment-variables)
- [Docker](#docker)
- [Cloud Deployment (AWS)](#cloud-deployment-aws)
- [Teardown](#teardown)
- [Cost Estimate](#cost-estimate)
- [Known Limitations](#known-limitations)

---

## Overview

This service is part of the AIRMAN Skynet Cloud Ops assessment.
It is intentionally minimal — the focus is on cloud deployment, observability, security, and cost-aware design.

**What it does:**
- Accepts operational/audit events via `POST /events`
- Stores them persistently using SQLite on EFS
- Returns filtered events via `GET /events`
- Exposes a health check at `GET /health`
- Supports observability testing via `GET /metrics-demo`

---

## Architecture

```
Internet
    │
    ▼
ALB (Application Load Balancer)
    │  port 80
    ▼
ECS Fargate (container)
    │  FastAPI + SQLite
    ▼
EFS (Elastic File System)
    └── /app/data/events.db  ← persistent SQLite file

Secrets   → AWS SSM Parameter Store
Logs      → CloudWatch Logs (7 day retention)
Alerts    → CloudWatch Alarms (error rate, latency, health)
Budget    → AWS Budgets ($50/month alert)
IaC       → Terraform
```

---

## Tech Stack

| Layer       | Technology               | Reason                                      |
|-------------|--------------------------|---------------------------------------------|
| Runtime     | Python 3.12 + FastAPI    | Fast, minimal, auto docs, familiar          |
| Storage     | SQLite on EFS            | No managed DB cost, persists across restarts|
| Container   | Docker (multi-stage)     | Small image, non-root user, healthcheck     |
| Compute     | AWS ECS Fargate          | Serverless containers, no EC2 to manage     |
| Networking  | AWS ALB                  | Health checks, single entry point           |
| Secrets     | AWS SSM Parameter Store  | Secure, no secrets in code or env files     |
| Logs        | AWS CloudWatch Logs      | Structured JSON logs, 7 day retention       |
| Monitoring  | AWS CloudWatch Alarms    | Error rate, latency, unhealthy host alerts  |
| IaC         | Terraform                | Reproducible, version controlled infra      |

---

## Project Structure

```
skynet-ops-audit-service/
├── app/
│   ├── __init__.py
│   ├── main.py          # FastAPI app, all routes, middleware
│   ├── config.py        # Environment variable config
│   └── database.py      # SQLite connection and schema
├── infra/
│   ├── main.tf          # Provider and backend config
│   ├── variables.tf     # All input variables
│   ├── networking.tf    # VPC, subnets, ALB, security groups
│   ├── ecs.tf           # ECR, ECS cluster, task, service, IAM
│   ├── efs.tf           # EFS file system and mount targets
│   ├── monitoring.tf    # CloudWatch alarms and budget alerts
│   ├── outputs.tf       # Output values after deploy
│   └── terraform.tfvars.example
├── docs/
│   ├── cost-report.md
│   ├── Observability.md
│   ├── runbook.md
│   ├── security.md
├── .env.example
├── .gitignore
├── Dockerfile
├── requirements.txt
├── submission_checklist.md
└── README.md


```

---

## Local Setup

### Prerequisites
- Docker installed
- Python 3.12+ (if running without Docker)

### Run with Docker (recommended)

```bash
# 1. Clone the repo
git clone <your-repo-url>
cd skynet-ops-audit-service

# 2. Copy env file
cp .env.example .env

# 3. Build the image
docker build -t skynet-ops-audit-service .

# 4. Run the container
docker run -p 8000:8000 --env-file .env skynet-ops-audit-service:latest
```

### Run without Docker

```bash
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --port 8000
```

### Test Endpoints Locally

```bash
# Health check
curl http://localhost:8000/health

# Post an event
curl -X POST http://localhost:8000/events \
  -H "Content-Type: application/json" \
  -d '{
    "type": "roster_update",
    "tenantId": "academy_001",
    "severity": "info",
    "message": "Instructor schedule adjusted for morning slot",
    "source": "skynet-api"
  }'

# Get events
curl http://localhost:8000/events

# Get events with filters
curl "http://localhost:8000/events?tenantId=academy_001&severity=info&limit=10"

# Test validation (expect 422)
curl -X POST http://localhost:8000/events \
  -H "Content-Type: application/json" \
  -d '{"type": "test", "tenantId": "", "severity": "invalid", "message": "", "source": "x"}'

# Metrics demo
curl "http://localhost:8000/metrics-demo?mode=error"
curl "http://localhost:8000/metrics-demo?mode=slow"
curl "http://localhost:8000/metrics-demo?mode=burst"
```

---

## API Endpoints

### `GET /health`
Returns service health status.

**Response 200:**
```json
{
  "status": "ok",
  "service": "skynet-ops-audit-service",
  "environment": "dev",
  "timestamp": "2026-03-09T18:00:00Z"
}
```

---

### `POST /events`
Ingest a single operational/audit event.

**Required fields:** `type`, `tenantId`, `severity`, `message`, `source`
**Optional fields:** `metadata`, `occurredAt`, `traceId`
**Severity values:** `info`, `warning`, `error`, `critical`

**Request:**
```json
{
  "type": "roster_update",
  "tenantId": "academy_001",
  "severity": "info",
  "message": "Instructor schedule adjusted for morning slot",
  "source": "skynet-api",
  "metadata": { "instructorId": "ins_014" }
}
```

**Response 201:**
```json
{
  "success": true,
  "eventId": "evt_a1b2c3d4e5f6",
  "storedAt": "2026-03-09T18:00:00Z"
}
```

---

### `GET /events`
Returns stored events, newest first.

**Query parameters:**

| Param      | Type    | Default | Description              |
|------------|---------|---------|--------------------------|
| `tenantId` | string  | -       | Filter by tenant         |
| `severity` | string  | -       | Filter by severity level |
| `type`     | string  | -       | Filter by event type     |
| `limit`    | integer | 20      | Max results (max 100)    |
| `offset`   | integer | 0       | Pagination offset        |

**Example:**
```bash
GET /events?tenantId=academy_001&severity=warning&limit=10
```

---

### `GET /metrics-demo`
Simulates traffic patterns for observability testing.

| Mode    | Behaviour                        |
|---------|----------------------------------|
| `error` | Returns HTTP 500                 |
| `slow`  | Sleeps 2 seconds then responds   |
| `burst` | Emits 10 log lines rapidly       |
| _(none)_| Returns 200 ok                   |

---

## Environment Variables

| Variable               | Required | Default                   | Description                        |
|------------------------|----------|---------------------------|------------------------------------|
| `APP_ENV`              | No       | `dev`                     | Environment name                   |
| `PORT`                 | No       | `8000`                    | Server port                        |
| `LOG_LEVEL`            | No       | `info`                    | Logging verbosity                  |
| `STORE_BACKEND`        | No       | `sqlite`                  | Storage backend                    |
| `DB_URL`               | No       | `./data/events.db`        | SQLite file path                   |
| `METRICS_DEMO_ENABLED` | No       | `true`                    | Enable /metrics-demo endpoint      |
| `MAX_EVENTS_LIMIT`     | No       | `100`                     | Max limit for GET /events          |
| `API_KEY`              | No       | _(empty = auth disabled)_ | Optional API key for auth          |
| `SERVICE_NAME`         | No       | `skynet-ops-audit-service`| Service name in logs               |

---

## Docker

### Build
```bash
docker build -t skynet-ops-audit-service .
```

### Run
```bash
docker run -p 8000:8000 \
  -v $(pwd)/data:/app/data \
  --env-file .env \
  skynet-ops-audit-service:latest
```

### Key Dockerfile decisions
- **Multi-stage build** — keeps final image small (~55MB)
- **Non-root user** — runs as `appuser` for security
- **HEALTHCHECK** built in — Docker and ECS use this
- **PYTHONUNBUFFERED=1** — logs appear immediately, not buffered

---

## CI/CD (GitHub Actions)

Every push to `main` automatically builds the Docker image, pushes it to ECR, and deploys to ECS.

### Setup (one time)

1. Create a least-privilege IAM user (`skynet-cicd`) — see `docs/security.md` for the exact policy
2. Add secrets to GitHub: `Settings → Secrets and variables → Actions`

| Secret | Value |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |

### How it works

```
git push main
    │
    ▼
GitHub Actions
    ├── Build Docker image
    ├── Push :latest + :<git-sha> to ECR
    └── Force new ECS deployment
            │
            ▼
    Wait for service stable
            │
            ▼
    ✅ New version live
```

Images are tagged with both `:latest` (for ECS to pull) and `:<git-sha>` (for precise rollback to any commit).

The pipeline file is at `.github/workflows/deploy.yml`.

---

## Cloud Deployment (AWS)

### Prerequisites
- AWS CLI configured (`aws configure`)
- Terraform >= 1.5.0 installed
- Docker installed

### Step 1 — Push image to ECR (first time / manual)

```bash
# Set your AWS account ID and region
export AWS_ACCOUNT_ID=123456789012
export AWS_REGION=ap-south-1

# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS \
  --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build, tag and push
docker build -t skynet-ops-audit-service .
docker tag skynet-ops-audit-service:latest \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/skynet-ops-audit-service:latest
docker push \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/skynet-ops-audit-service:latest
```

### Step 2 — Deploy with Terraform

```bash
cd infra

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set image_uri to your ECR URL

terraform init
terraform validate
terraform plan
terraform apply
```

### Step 3 — Get the service URL

```bash
terraform output alb_dns_name
# → http://skynet-ops-audit-service-alb-xxxxxxx.ap-south-1.elb.amazonaws.com
```

### Step 4 — Test the deployed service

```bash
export SERVICE_URL=$(terraform output -raw alb_dns_name)

curl $SERVICE_URL/health
curl -X POST $SERVICE_URL/events \
  -H "Content-Type: application/json" \
  -d '{"type":"roster_update","tenantId":"academy_001","severity":"info","message":"test","source":"manual"}'
```

---

## Teardown

**Always run this to avoid ongoing charges:**

```bash
cd infra
terraform destroy
```

**Also manually clean up:**
```bash
# Delete ECR images
aws ecr delete-repository \
  --repository-name skynet-ops-audit-service \
  --force \
  --region ap-south-1

# Delete CloudWatch log group (if not destroyed by terraform)
aws logs delete-log-group \
  --log-group-name /ecs/skynet-ops-audit-service \
  --region ap-south-1
```

> **Note:** EFS may retain data after destroy. Check AWS console and manually delete if needed.

---

## Cost Estimate

Estimated monthly cost for pilot scale (1-3 tenants, ~5,000-20,000 requests/day):

| Component              | Est. Monthly Cost |
|------------------------|-------------------|
| ECS Fargate (0.25 vCPU, 512MB) | ~$8-12   |
| ALB                    | ~$16-18           |
| EFS (< 1GB data)       | ~$0.30            |
| CloudWatch Logs (7d)   | ~$1-2             |
| SSM Parameter Store    | ~$0               |
| ECR Storage            | ~$0.10            |
| **Total**              | **~$26-32/month** |

Within the $25-75/month pilot budget. ✅

### Cost controls in place
- Log retention set to 7 days only
- Fargate minimum size (0.25 vCPU / 512MB)
- ECR lifecycle policy keeps only last 3 images
- EFS lifecycle policy moves data to IA after 7 days
- Budget alert at 80% of $50/month

---

## Known Limitations

1. **SQLite single-writer** — EFS+SQLite works for `desired_count=1`. Scaling to multiple containers would require migrating to RDS PostgreSQL.
2. **No HTTPS** — ALB is HTTP only. Production would need an ACM certificate and HTTPS listener.
3. **SQLite not ideal for high write throughput** — acceptable at 200-2000 events/day pilot scale.
4. **No authentication by default** — `API_KEY` is optional. Production should enforce it.
5. **Dev environment always on** — no auto scale-to-zero in current setup. Can be improved with ECS scheduled scaling.
6. **Terraform does not update on CI/CD push** — infra changes still require a manual `terraform apply`. App code changes deploy automatically via GitHub Actions.
