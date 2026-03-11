# AIRMAN Skynet Cloud Ops Intern Assessment — Submission Checklist

---

## 1) Candidate & Submission Info

- **Name:** Blessed Retna Singh B S
- **Email:** blessedretnasinghbs@gmail.com
- **Chosen Cloud Platform:** AWS
- **Assessment Level Submitted:** Level 1 and 2 
- **Level 2 Option Chosen :** CI/CD implemented
- **GitHub Repo Link:** https://github.com/Blessed-13/skynet-ops-audit-service.git
- **Demo Video Link (optional but recommended):** [Your Demo Video URL]
- **Submission Date (UTC):** 12/03/2026

---

## 2) What I Implemented (Summary)

### Level 1
- [x] Mini service (`/health`, `POST /events`, `GET /events`, `GET /metrics-demo`)
- [x] Dockerized service
- [x] Cloud deployment — AWS ECS Fargate via Terraform (IaC-backed deploy plan)
- [x] Infrastructure as Code — Terraform
- [x] Cost optimization report
- [x] Observability setup — CloudWatch Logs + CloudWatch Alarms
- [x] Security/secrets approach — AWS SSM Parameter Store, non-root container, least-privilege IAM
- [x] Ops runbook — 6 scenarios covered
- [x] README with setup + teardown

---

## 3) Repository Structure

### Service Code
- Service path: `./app/`
- Main entry file: `./app/main.py`
- Local run command: `uvicorn app.main:app --reload --port 8000`

### Docker
- Dockerfile path: `./Dockerfile`
- `.dockerignore` path: `./.dockerignore`

### Infrastructure as Code
- IaC tool used: Terraform
- IaC root path: `./infra/`
- Environment config files: `./infra/terraform.tfvars.example`

### Docs
- README path: `./README.md`
- Cost report path: `./docs/cost-report.md`
- Runbook path: `./docs/runbook.md`
- Observability notes: `./docs/observability.md`
- Security/secrets notes: `./docs/security.md`

---

## 4) Local Run Instructions

### Prerequisites
- [x] Docker installed
- [x] Python 3.12+ installed (if running without Docker)
- [x] Terraform >= 1.5.0 installed
- [x] AWS CLI installed and configured (`aws configure`)

### Local Setup
```bash
git clone <your-repo-url>
cd skynet-ops-audit-service
cp .env.example .env
```

### Run Service Locally
```bash
# With Docker
docker build -t skynet-ops-audit-service .
docker run -p 8000:8000 --env-file .env skynet-ops-audit-service:latest

# Without Docker
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

### Test Endpoints Locally
```bash
# Health
curl http://localhost:8000/health

# Post event
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

# Test validation — expect 422
curl -X POST http://localhost:8000/events \
  -H "Content-Type: application/json" \
  -d '{"type":"test","tenantId":"","severity":"bad","message":"","source":"x"}'

# Metrics demo
curl "http://localhost:8000/metrics-demo?mode=error"
curl "http://localhost:8000/metrics-demo?mode=slow"
curl "http://localhost:8000/metrics-demo?mode=burst"
```

---

## 5) API Endpoint Checklist (Functional Validation)

### Health
- [x] `GET /health` works — returns `{"status": "ok", ...}`

### Events
- [x] `POST /events` stores an event — returns 201 with `eventId`
- [x] `GET /events` returns events — paginated, newest first
- [x] Validation rejects bad payloads — returns 422 with field errors

### Optional
- [x] `GET /metrics-demo` implemented
- [x] Route simulates latency (`?mode=slow`), errors (`?mode=error`), burst logs (`?mode=burst`)

---

## 6) Cloud Deployment Summary

### Deployment Type
- [x] IaC + deploy plan (Terraform — ready to apply with real AWS credentials)

### Cloud Services Used

- **Compute:** AWS ECS Fargate (0.25 vCPU / 512MB)
- **Storage/DB:** SQLite on AWS EFS (Elastic File System)
- **Networking/Ingress:** AWS ALB (Application Load Balancer), VPC, public subnets
- **Logging/Monitoring:** AWS CloudWatch Logs, CloudWatch Alarms (3 alarms)
- **Secrets:** AWS SSM Parameter Store (SecureString)
- **Budgeting/Alerts:** AWS Budgets ($50/month, alert at 80%)
- **Container Registry:** AWS ECR (with lifecycle policy — keep last 3 images)
- **IAM / Service Account:** ECS Task Execution Role + ECS Task Role (least privilege)

### Why I chose this architecture
- **ECS Fargate** — serverless containers, no EC2 to manage, scales to match pilot workload, pay only for what runs
- **SQLite on EFS** — avoids RDS cost (~$15-25/month saved), EFS persists data across container restarts, appropriate for 200-2,000 events/day pilot scale
- **ALB** — built-in health checks, single ingress point, ECS tasks not directly exposed to internet
- **SSM Parameter Store** — secrets never in code, env files, or Docker images
- **Terraform** — all infra reproducible, version controlled, easy to destroy cleanly

### Pilot Cost-Awareness Notes
- Total estimated cost: **~$29/month** — within $25-75/month budget
- ALB is the biggest cost driver (~$16.50/month) — acceptable at pilot scale, can be replaced with API Gateway HTTP API if budget tightens
- No NAT Gateway — public subnets used, saves ~$32/month
- No RDS — SQLite on EFS saves ~$15-25/month vs RDS t3.micro
- ECR lifecycle policy and EFS-IA transition keep storage costs near zero

---

## 7) Cost Optimization Report

- [x] Monthly estimate included — **~$29/month**
- [x] Assumptions documented — see `docs/cost-report.md`
- [x] Component-wise cost breakdown included

### Cost Controls Implemented
- [x] AWS Budget alert at $50/month (fires at 80%)
- [x] CloudWatch log retention set to 7 days
- [x] Resource tags on all AWS resources for cost tracking
- [x] ECR lifecycle policy — keep only last 3 images
- [x] EFS lifecycle — move to Infrequent Access after 7 days
- [x] Single ECS task (`desired_count=1`) — no over-provisioning
- [x] Teardown (`terraform destroy`) instructions documented

### Common Cost Traps Accounted For
1. Idle compute instances — Fargate, no idle EC2
2. Overprovisioned managed DB — SQLite on EFS instead of RDS
3. Excessive logging — LOG_LEVEL=info, 7 day retention
4. NAT Gateway costs — public subnets, no NAT Gateway needed
5. Snapshots and unattached disks — no EBS volumes used
6. Static IPs / load balancers left running — ALB destroyed with terraform destroy
7. Cross-region traffic — all resources in ap-south-1
8. Container registry accumulation — ECR lifecycle policy
9. CloudWatch log retention not set — explicitly set to 7 days
10. Over-engineering for 99.99% HA — single task, 99.0% pilot target

---

## 8) Observability & Monitoring

### Logging
- [x] Structured JSON logs implemented — every request logged with `timestamp`, `level`, `method`, `path`, `status`, `duration_ms`
- [x] Log level configurable via `LOG_LEVEL` env var
- [x] Logs shipped to CloudWatch via `awslogs` driver

### Sample Log Output
```json
{
  "timestamp": "2026-03-09T18:00:00Z",
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

### Metrics
- [x] Request latency — `duration_ms` logged on every request, ALB `TargetResponseTime` metric
- [x] Error count / error rate — ALB `HTTPCode_Target_5XX_Count` metric
- [x] Traffic volume — ALB `RequestCount` metric
- [x] Health signal — ALB `UnHealthyHostCount` metric + ECS health checks

### Alerts
- [x] **Alert 1 — High Error Rate:** > 5 HTTP 5xx errors/minute over 2 evaluation periods
  - Rationale: At pilot scale, 5 errors/minute signals a real problem not noise
- [x] **Alert 2 — High Latency:** Average response time > 1 second over 2 evaluation periods
  - Rationale: Target is POST < 500ms, GET < 1000ms — 1s average means something is wrong
- [x] **Alert 3 — Unhealthy Hosts:** Any unhealthy ECS task
  - Rationale: Single task deployment — any unhealthy host means service is degraded

---

## 9) Security / Secrets / IAM

### Secrets
- [x] No secrets committed to repo — `.env` in `.gitignore`
- [x] `.env.example` included with placeholder values only
- [x] Secrets management — API_KEY stored in AWS SSM Parameter Store as SecureString, injected into container at runtime via ECS secrets

### IAM / Access Control
- [x] **ECS Execution Role** — only `AmazonECSTaskExecutionRolePolicy` + SSM read for `/skynet-ops-audit-service/*`
- [x] **ECS Task Role** — only EFS ClientMount, ClientWrite, ClientRootAccess on specific EFS ARN
- [x] Least-privilege — no wildcard `*` actions or resources
- [x] Dangerous permissions identified — no S3, no IAM, no EC2 permissions granted to the service

### Security Basics
- [x] Container runs as non-root user (`appuser`) — reduces blast radius if container is compromised
- [x] Multi-stage Docker build — no build tools in final image
- [x] ECS tasks only accessible via ALB — security group blocks direct internet access
- [x] EFS encrypted at rest and in transit
- [x] ECR image scanning on push enabled

---

## 10) Ops Runbook

- Runbook file path: `./docs/runbook.md`

### Covered Scenarios
- [x] Service down / health checks failing
- [x] Latency spike
- [x] Sudden cost spike
- [x] DB/storage issue
- [x] Bad deployment / rollback
- [x] Accidental public exposure / misconfiguration

---

## 11) IaC Validation / Reproducibility

### Terraform
- [x] `terraform init` works
- [x] `terraform validate` works
- [x] `terraform plan` works
- [x] All variables documented in `variables.tf` with descriptions and defaults
- [x] Outputs documented in `outputs.tf` — ALB URL, ECR URL, ECS cluster/service names, log group

### Teardown
- [x] `terraform destroy` documented in README and runbook
- [x] Manual cleanup steps noted — ECR, CloudWatch Log Groups, EFS may persist after destroy

---

## 12) Known Limitations / Trade-offs

1. **SQLite single-writer** — EFS+SQLite works correctly for `desired_count=1`. Scaling to multiple containers would require migrating to RDS PostgreSQL. Noted as intentional pilot trade-off.
2. **No HTTPS** — ALB is HTTP only. Production would need an ACM certificate and HTTPS listener on port 443.
3. **No auto scale-to-zero** — Dev environment runs 24/7. Scheduled ECS scaling (scale to 0 overnight) would reduce costs further.
4. **No CI/CD pipeline** — Deployment is manual (`docker push` + `terraform apply`). A GitHub Actions pipeline would improve deployment safety.
5. **ALB cost at pilot scale** — ALB fixed cost (~$16.50/month) is high relative to total budget. API Gateway HTTP API would be cheaper but requires refactoring.

---

## 13) AI Tool Usage Disclosure

### AI tools used
- [x] Claude

### What I used AI for
- Scaffolding the FastAPI service structure
- Writing Terraform resource definitions
- Drafting the runbook, cost report, and README

### What I manually verified / tested
- Docker build and run locally
- All API endpoints tested with curl
- Dockerfile fixes (PYTHONPATH, PYTHONUNBUFFERED)
- Reviewed all Terraform files for correctness
- Cost estimates verified against AWS pricing calculator

---

## 14) Final Notes

This submission focuses on the Cloud Ops fundamentals the assessment prioritizes:
cost-aware architecture, operational clarity, security defaults, and observability.

The service is intentionally minimal — a FastAPI app with SQLite on EFS — because
the workload (200-2,000 events/day, pilot scale) does not justify a more complex stack.

All infrastructure is defined in Terraform and can be fully deployed and destroyed
with standard commands. No manual AWS console steps are required for deployment.
