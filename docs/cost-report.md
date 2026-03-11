# Cost Optimization Report — skynet-ops-audit-service

> Pilot scale deployment for AIRMAN Skynet (1-3 flight training academies)
> Cloud: AWS | Region: ap-south-1 (Mumbai)
> Target budget: $25-75/month

---

## Workload Assumptions

| Parameter                  | Value                                 |
|----------------------------|---------------------------------------|
| Tenants                    | 1-3 flight training academies         |
| Requests/day               | 5,000 - 20,000                        |
| Events stored/day          | 200 - 2,000                           |
| Storage growth/month       | ~10 MB - 250 MB                       |
| Traffic pattern            | Bursty, 70% within 10-hour window     |
| Availability target        | ~99.0% (pilot acceptable)             |
| Environments               | 1 dev environment                     |
| Log retention              | 7 days (dev/pilot)                    |

---

## Monthly Cost Estimate

### Component Breakdown

| Component                        | Spec                        | Est. Monthly Cost |
|----------------------------------|-----------------------------|-------------------|
| ECS Fargate                      | 0.25 vCPU, 512MB, 24/7      | ~$10.00           |
| ALB (Application Load Balancer)  | 1 ALB, low LCU usage        | ~$16.50           |
| EFS (Elastic File System)        | <1GB data, bursting mode    | ~$0.33            |
| CloudWatch Logs                  | 7 day retention, ~1GB/month | ~$1.50            |
| CloudWatch Alarms                | 3 alarms                    | ~$0.30            |
| ECR (Container Registry)         | <1GB storage                | ~$0.10            |
| SSM Parameter Store              | 1 SecureString param        | ~$0.00            |
| Data Transfer                    | Low egress, same region     | ~$0.50            |
| **Total**                        |                             | **~$29/month**    |

✅ Within the $25-75/month pilot budget.

---

### Fargate Cost Calculation

```
vCPU cost:   0.25 vCPU × $0.04048/vCPU-hour × 730 hours = ~$7.39/month
Memory cost: 0.5 GB   × $0.004445/GB-hour   × 730 hours = ~$1.62/month
Total Fargate: ~$9.01/month
```

### ALB Cost Calculation

```
Fixed cost:  $0.022/hour × 730 hours         = ~$16.06/month
LCU cost:    minimal at pilot traffic scale  = ~$0.50/month
Total ALB:   ~$16.56/month
```

> Note: ALB is the biggest cost driver. At pilot scale this is acceptable.
> If cost needs to be reduced further, replace ALB with an API Gateway HTTP API (~$3.50/month)
> but that requires architectural changes.

---

## Cost Controls Implemented

### 1. Fargate Minimum Sizing
Using the smallest available Fargate size (0.25 vCPU / 512MB).
Pilot workload of 5,000-20,000 requests/day is well within this capacity.

```hcl
# terraform.tfvars
container_cpu    = 256   # 0.25 vCPU
container_memory = 512   # 512 MB
```

### 2. CloudWatch Log Retention — 7 Days
Logs older than 7 days are automatically deleted.
Sufficient for debugging pilot issues without accumulating unnecessary storage costs.

```hcl
variable "log_retention_days" {
  default = 7
}
```

### 3. ECR Lifecycle Policy — Keep Only Last 3 Images
Old Docker images are automatically deleted from ECR.
Prevents container registry storage from accumulating over time.

```hcl
rules = [{
  rulePriority = 1
  description  = "Keep only last 3 images"
  selection = {
    countType   = "imageCountMoreThan"
    countNumber = 3
  }
  action = { type = "expire" }
}]
```

### 4. EFS Lifecycle Policy — Move to Infrequent Access After 7 Days
Files not accessed for 7 days are automatically moved to EFS-IA storage
which costs ~92% less than standard EFS storage.

```hcl
lifecycle_policy {
  transition_to_ia = "AFTER_7_DAYS"
}
```

### 5. AWS Budget Alert — $50/month
Alert fires at 80% ($40) actual spend and 100% ($50) forecasted spend.
Gives early warning before budget is exceeded.

```hcl
variable "monthly_budget_usd" {
  default = 50
}
```

### 6. SQLite on EFS Instead of RDS
Using SQLite on EFS instead of a managed RDS instance saves ~$15-30/month.

| Option              | Est. Monthly Cost |
|---------------------|-------------------|
| RDS PostgreSQL (t3.micro) | ~$15-25/month |
| SQLite on EFS       | ~$0.33/month      |
| **Saving**          | **~$15-25/month** |

Justified because pilot workload is 200-2,000 events/day — well within SQLite's capability.

### 7. Single Desired Count
Running only 1 ECS task for the pilot.
No need for multiple replicas at this scale — saves ~50% compute cost vs running 2 tasks.

```hcl
variable "desired_count" {
  default = 1
}
```

### 8. Resource Tagging for Cost Tracking
All AWS resources are tagged with `Project`, `Environment`, and `ManagedBy`.
This allows filtering by tag in AWS Cost Explorer to see exactly what this service costs.

```hcl
default_tags {
  tags = {
    Project     = "skynet-ops-audit-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

---

## Common Cost Traps — Accounted For

| # | Cost Trap                          | How We Avoided It                                          |
|---|------------------------------------|------------------------------------------------------------|
| 1 | Idle compute instances             | Fargate — no idle EC2, pay only for running tasks          |
| 2 | Overprovisioned managed DB         | SQLite on EFS instead of RDS                               |
| 3 | Excessive logging / trace volume   | LOG_LEVEL=info, 7 day retention, no X-Ray tracing          |
| 4 | NAT Gateway costs                  | Public subnets used — no NAT Gateway needed (~$32/month saved) |
| 5 | Snapshots and unattached disks     | No EBS volumes — EFS only, no snapshots configured         |
| 6 | Static IPs / load balancers running idle | ALB tied to active service, destroyed with terraform destroy |
| 7 | Cross-region traffic               | All resources in same region (ap-south-1)                  |
| 8 | Container registry accumulation    | ECR lifecycle policy keeps only last 3 images              |
| 9 | Log retention not set              | Explicitly set to 7 days — CloudWatch default is never-expire |
|10 | Over-engineering for 99.99% HA     | Single task, 99.0% target — appropriate for pilot          |

---

## Cost Optimization Opportunities (Future)

If cost needs to be reduced further in later stages:

| Opportunity                        | Potential Saving       |
|------------------------------------|------------------------|
| Replace ALB with API Gateway HTTP API | ~$13/month          |
| Scale ECS to 0 outside working hours  | ~$5-7/month          |
| Move to ARM64 (Graviton) Fargate      | ~20% compute saving  |
| Reduce log retention to 3 days        | ~$0.50/month         |

---

## Storage Estimate

| Item                        | Size             |
|-----------------------------|------------------|
| Events (200/day × 30 days)  | ~18 MB/month     |
| Events (2000/day × 30 days) | ~180 MB/month    |
| SQLite overhead             | ~10-20%          |
| **Total EFS usage**         | **~20-220 MB/month** |

Well within EFS free tier (5GB) for the first 12 months on a new AWS account.

---

## Teardown / Destroy Instructions

**Run this when done to avoid ongoing charges:**

```bash
cd infra
terraform destroy
```

**Manually verify these are deleted:**
- [ ] ECS Cluster — AWS Console → ECS
- [ ] ALB — AWS Console → EC2 → Load Balancers
- [ ] EFS — AWS Console → EFS (may retain data)
- [ ] ECR — manually delete if needed: `aws ecr delete-repository --repository-name skynet-ops-audit-service --force`
- [ ] CloudWatch Log Groups — may persist after destroy
- [ ] SSM Parameters — `aws ssm delete-parameter --name /skynet-ops-audit-service/API_KEY`

> EFS and CloudWatch Log Groups sometimes survive `terraform destroy`.
> Always check the AWS Console after running destroy.
