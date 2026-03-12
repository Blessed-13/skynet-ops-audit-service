# Ops Runbook — skynet-ops-audit-service

> This runbook covers common operational scenarios for the skynet-ops-audit-service
> running on AWS ECS Fargate. Follow these steps when alerts fire or issues are reported.

---

## Quick Reference

| What                  | Where                                                                 |
|-----------------------|-----------------------------------------------------------------------|
| Service URL           | `terraform output alb_dns_name`                                       |
| ECS Cluster           | AWS Console → ECS → skynet-ops-audit-service-cluster                 |
| CloudWatch Logs       | AWS Console → CloudWatch → Log Groups → /ecs/skynet-ops-audit-service |
| CloudWatch Alarms     | AWS Console → CloudWatch → Alarms                                     |
| SSM Secrets           | AWS Console → Systems Manager → Parameter Store                       |
| EFS                   | AWS Console → EFS → skynet-ops-audit-service-efs                     |

---

## Scenario 1 — Service Down / Health Checks Failing

**Symptoms:**
- `GET /health` returns non-200 or times out
- CloudWatch alarm `skynet-ops-audit-service-unhealthy-hosts` is firing
- ALB returning 502/503

**Steps:**

### 1. Check ECS task status
```bash
aws ecs list-tasks \
  --cluster skynet-ops-audit-service-cluster \
  --region ap-south-1

# Describe the task to see why it stopped
aws ecs describe-tasks \
  --cluster skynet-ops-audit-service-cluster \
  --tasks <task-id> \
  --region ap-south-1
```
Look at `stopCode` and `stoppedReason` in the output.

### 2. Check application logs
```bash
aws logs tail /ecs/skynet-ops-audit-service \
  --follow \
  --region ap-south-1
```
Look for `ERROR` or exception tracebacks.

### 3. Force a new deployment (restart the task)
```bash
aws ecs update-service \
  --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service \
  --force-new-deployment \
  --region ap-south-1
```

### 4. Verify recovery
```bash
export SERVICE_URL=$(cd infra && terraform output -raw alb_dns_name)
curl $SERVICE_URL/health
```
Expected: `{"status": "ok", ...}`

### 5. If task keeps crashing — check EFS mount
```bash
# Check EFS mount targets are available
aws efs describe-mount-targets \
  --file-system-id <efs-id> \
  --region ap-south-1
```
If mount targets are unavailable, the container can't write to SQLite and will crash.

---

## Scenario 2 — High Latency

**Symptoms:**
- CloudWatch alarm `skynet-ops-audit-service-high-latency` is firing
- Average response time > 1 second
- Users reporting slow responses

**Steps:**

### 1. Check which endpoint is slow
```bash
# View recent logs and look for high duration_ms values
aws logs filter-log-events \
  --log-group-name /ecs/skynet-ops-audit-service \
  --filter-pattern '{ $.duration_ms > 500 }' \
  --region ap-south-1
```

### 2. Check if metrics-demo slow mode was triggered accidentally
```bash
aws logs filter-log-events \
  --log-group-name /ecs/skynet-ops-audit-service \
  --filter-pattern "metrics_demo_slow_triggered" \
  --region ap-south-1
```
If yes — this is expected behavior, not a real issue.

### 3. Check EFS performance
High EFS latency can slow down SQLite reads/writes.
- Go to AWS Console → EFS → skynet-ops-audit-service-efs → Monitoring
- Check `ClientReadIOPS` and `ClientWriteIOPS`
- If consistently high, consider switching to `maxIO` performance mode (higher cost)

### 4. Check ECS task CPU/Memory
```bash
# Check CloudWatch metrics for the ECS service
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=skynet-ops-audit-service-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average \
  --region ap-south-1
```
If CPU > 80% consistently — increase `container_cpu` in `terraform.tfvars` and redeploy.

### 5. Temporary fix — restart the task
```bash
aws ecs update-service \
  --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service \
  --force-new-deployment \
  --region ap-south-1
```

---

## Scenario 3 — Sudden Cost Spike

**Symptoms:**
- AWS Budget alert fired (>80% of $50/month)
- Unexpected charges in AWS Cost Explorer

**Steps:**

### 1. Check AWS Cost Explorer
- Go to AWS Console → Cost Explorer
- Filter by service
- Look for unusual spikes in: ECS, CloudWatch, EFS, Data Transfer

### 2. Common causes and fixes

**CloudWatch logs too verbose:**
```bash
# Check log volume
aws logs describe-log-groups \
  --log-group-name-prefix /ecs/skynet-ops-audit-service \
  --region ap-south-1
```
Fix — increase `LOG_LEVEL` to `warning` to reduce log volume:
```bash
# Update SSM or redeploy with LOG_LEVEL=warning
aws ecs update-service \
  --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service \
  --force-new-deployment \
  --region ap-south-1
```

**EFS storage growing unexpectedly:**
```bash
aws efs describe-file-systems \
  --region ap-south-1
```
Check `SizeInBytes`. If large — SQLite DB may have grown unexpectedly.

**metrics-demo generating synthetic traffic:**
Ensure no load test scripts are running against `/metrics-demo` in production.

### 3. Set a hard budget alert if not already done
- Go to AWS Console → Billing → Budgets
- Verify `skynet-ops-audit-service-monthly-budget` exists
- If missing — re-run `terraform apply`

### 4. If cost spike is unresolvable — scale down
```bash
# Scale ECS to 0 tasks temporarily
aws ecs update-service \
  --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service \
  --desired-count 0 \
  --region ap-south-1
```
> ⚠️ This takes the service offline. Only do this in dev/pilot environment.

---

## Scenario 4 — Storage / DB Issue

**Symptoms:**
- `POST /events` returning 500
- Logs show SQLite errors
- EFS mount failing

**Steps:**

### 1. Check logs for SQLite errors
```bash
aws logs filter-log-events \
  --log-group-name /ecs/skynet-ops-audit-service \
  --filter-pattern "ERROR" \
  --region ap-south-1
```

### 2. Verify EFS mount targets are healthy
```bash
aws efs describe-mount-targets \
  --file-system-id <efs-id> \
  --region ap-south-1
```
All mount targets should show `LifeCycleState: available`.

### 3. Restart the task to remount EFS
```bash
aws ecs update-service \
  --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service \
  --force-new-deployment \
  --region ap-south-1
```

### 4. If DB file is corrupted
SSH is not available with Fargate. To repair:
- Scale service to 0
- Use AWS EFS console to browse files (or mount EFS to a temporary EC2 instance)
- Delete or replace the corrupted `events.db`
- Scale service back to 1

---

## Scenario 5 — Bad Deployment / Rollback

**Symptoms:**
- New deployment broke the service
- Health checks failing after a GitHub Actions deploy
- GitHub Actions pipeline failed mid-deploy

**Steps:**

### Option A — Rollback via git SHA image tag (preferred)

Every CI/CD deploy pushes two tags: `:latest` and `:<git-sha>`.
You can redeploy any previous commit's image directly.

```bash
# 1. Find the last known good commit SHA from GitHub Actions history
#    (check the Actions tab in GitHub for the last green deploy)
export GOOD_SHA=abc1234   # replace with actual SHA

export ECR_URL=<your-account-id>.dkr.ecr.ap-south-1.amazonaws.com/skynet-ops-audit-service

# 2. Re-tag the good image as :latest
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin $ECR_URL

docker pull $ECR_URL:$GOOD_SHA
docker tag $ECR_URL:$GOOD_SHA $ECR_URL:latest
docker push $ECR_URL:latest

# 3. Force new ECS deployment with the restored :latest
aws ecs update-service \
  --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service \
  --force-new-deployment \
  --region ap-south-1
```

### Option B — Rollback via ECS task definition revision

```bash
# List previous task definition revisions
aws ecs list-task-definitions \
  --family-prefix skynet-ops-audit-service \
  --region ap-south-1

# Roll back to a specific revision
aws ecs update-service \
  --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service \
  --task-definition skynet-ops-audit-service:<previous-revision> \
  --region ap-south-1
```

### Verify rollback succeeded
```bash
export SERVICE_URL=$(cd infra && terraform output -raw alb_dns_name)
curl $SERVICE_URL/health
```

### Fix and redeploy
Fix the issue in code and push to `main` — GitHub Actions will build and deploy automatically.

---

## Scenario 6 — Accidental Public Exposure / Misconfiguration

**Symptoms:**
- ECS tasks directly accessible from internet (not via ALB)
- SSM secrets visible in code or logs
- Unexpected IAM permissions

**Steps:**

### 1. Verify ECS security group only allows ALB traffic
```bash
aws ec2 describe-security-groups \
  --filters Name=group-name,Values=skynet-ops-audit-service-ecs-sg \
  --region ap-south-1
```
The inbound rule should only allow traffic from the ALB security group on port 8000.
If you see `0.0.0.0/0` as the source — run `terraform apply` to fix it immediately.

### 2. Verify no secrets in logs
```bash
aws logs filter-log-events \
  --log-group-name /ecs/skynet-ops-audit-service \
  --filter-pattern "API_KEY" \
  --region ap-south-1
```
If API_KEY appears in logs — rotate it immediately in SSM Parameter Store.

### 3. Rotate the API key
```bash
aws ssm put-parameter \
  --name /skynet-ops-audit-service/API_KEY \
  --value "new-secure-key-here" \
  --type SecureString \
  --overwrite \
  --region ap-south-1

# Restart service to pick up new key
aws ecs update-service \
  --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service \
  --force-new-deployment \
  --region ap-south-1
```

### 4. Audit IAM permissions
```bash
aws iam get-role-policy \
  --role-name skynet-ops-audit-service-ecs-task-role \
  --policy-name skynet-ops-audit-service-efs-access \
  --region ap-south-1
```
Permissions should be limited to EFS access only. No `*` wildcards.

---

## Alert Thresholds Reference

| Alarm                  | Threshold          | Rationale                                      |
|------------------------|--------------------|------------------------------------------------|
| High error rate        | > 5 errors/min     | Pilot scale — 5 errors/min indicates real issue|
| High latency           | avg > 1 second     | POST /events target < 500ms, GET < 1000ms      |
| Unhealthy hosts        | > 0 unhealthy      | Any unhealthy host needs immediate attention   |
| Budget alert           | > 80% of $50/month | Early warning before overspend                 |

---

## Useful Commands

```bash
# View live logs
aws logs tail /ecs/skynet-ops-audit-service --follow --region ap-south-1

# List running tasks
aws ecs list-tasks --cluster skynet-ops-audit-service-cluster --region ap-south-1

# Force restart
aws ecs update-service --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service --force-new-deployment --region ap-south-1

# Scale down (emergency)
aws ecs update-service --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service --desired-count 0 --region ap-south-1

# Scale back up
aws ecs update-service --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service --desired-count 1 --region ap-south-1

# Destroy everything
cd infra && terraform destroy
```
