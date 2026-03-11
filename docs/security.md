# Security & Secrets — skynet-ops-audit-service

> This document covers secrets management, IAM design, container security,
> and network access controls for the skynet-ops-audit-service.

---

## Secrets Management

### Approach — AWS SSM Parameter Store
All secrets are stored in **AWS SSM Parameter Store** as `SecureString` (encrypted with KMS).
Secrets are never stored in:
- Source code
- Dockerfile
- `.env` files committed to git
- Environment variable plaintext in ECS task definition

### How it works
```
SSM Parameter Store
  └── /skynet-ops-audit-service/API_KEY  (SecureString)
            │
            ▼
  ECS Task Definition (secrets block)
            │
            ▼
  Container receives as environment variable at runtime
  (value never visible in AWS Console task definition)
```

### Parameters Stored

| Parameter                             | Type         | Description                  |
|---------------------------------------|--------------|------------------------------|
| `/skynet-ops-audit-service/API_KEY`   | SecureString | Optional API auth key        |

### Rotating a Secret
```bash
# Update the value in SSM
aws ssm put-parameter \
  --name /skynet-ops-audit-service/API_KEY \
  --value "new-secure-value" \
  --type SecureString \
  --overwrite \
  --region ap-south-1

# Restart ECS service to pick up new value
aws ecs update-service \
  --cluster skynet-ops-audit-service-cluster \
  --service skynet-ops-audit-service-service \
  --force-new-deployment \
  --region ap-south-1
```

### .env.example
A `.env.example` file is committed to the repo with placeholder values only.
The actual `.env` file is listed in `.gitignore` and never committed.

```bash
# .gitignore
.env
data/
```

---

## IAM Design — Least Privilege

Two separate IAM roles are used — one for task execution, one for the running task.

### Role 1 — ECS Task Execution Role
Used by ECS to pull the Docker image and set up the container.

**Permissions:**
- `AmazonECSTaskExecutionRolePolicy` — pull ECR image, write CloudWatch logs
- `ssm:GetParameter` / `ssm:GetParameters` — read secrets from SSM
- Scoped to: `arn:aws:ssm:ap-south-1:*:parameter/skynet-ops-audit-service/*`

**Does NOT have:**
- S3 access
- RDS access
- EC2 access
- IAM access
- Any wildcard `*` resource permissions

### Role 2 — ECS Task Role
Used by the running application container at runtime.

**Permissions:**
- `elasticfilesystem:ClientMount` — mount EFS
- `elasticfilesystem:ClientWrite` — write to EFS
- `elasticfilesystem:ClientRootAccess` — access EFS root directory
- Scoped to: specific EFS file system ARN only

**Does NOT have:**
- CloudWatch write access (logs handled by execution role)
- SSM access (secrets injected at startup, not read at runtime)
- Any other AWS service access

### Why Two Roles?
Separating execution role from task role means:
- If the application is compromised, it cannot pull new images or modify CloudWatch
- If the execution role is compromised, it cannot write to EFS or access app data
- Follows AWS security best practice of least privilege per component

---

## Container Security

### Non-Root User
The container runs as a non-root system user (`appuser`).

```dockerfile
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser
USER appuser
```

If the container process is exploited, the attacker has minimal system privileges.

### Multi-Stage Docker Build
The final image contains only the runtime — no build tools, no pip, no compilers.

```dockerfile
# Stage 1 — builder (has pip, build tools)
FROM python:3.12-slim AS builder
RUN pip install ...

# Stage 2 — runtime (clean, minimal)
FROM python:3.12-slim
COPY --from=builder /install /usr/local
# pip is NOT in the final image
```

This reduces the attack surface of the running container.

### ECR Image Scanning
ECR is configured to scan images on push for known CVEs:

```hcl
image_scanning_configuration {
  scan_on_push = true
}
```

Check scan results:
```bash
aws ecr describe-image-scan-findings \
  --repository-name skynet-ops-audit-service \
  --image-id imageTag=latest \
  --region ap-south-1
```

---

## Network Security

### ECS Tasks Not Directly Exposed
ECS tasks are in a security group that only accepts traffic from the ALB security group.
Direct internet access to the container on port 8000 is blocked.

```
Internet → ALB (port 80) → ECS Task (port 8000)
                ↑
         Only path allowed
```

### Security Group Rules

**ALB Security Group:**
- Inbound: port 80 from `0.0.0.0/0` (public internet)
- Outbound: all traffic

**ECS Security Group:**
- Inbound: port 8000 from ALB security group **only**
- Outbound: all traffic (needed for ECR pull, SSM, EFS, CloudWatch)

**EFS Security Group:**
- Inbound: port 2049 (NFS) from ECS security group **only**
- No direct internet access to EFS

### EFS Encryption
- **At rest** — EFS encrypted using AWS managed KMS key
- **In transit** — `transit_encryption = "ENABLED"` in ECS volume configuration

---

## CI/CD IAM User — Least Privilege

The GitHub Actions workflow needs an IAM user with only the permissions required
to build, push, and deploy. Never use your personal AWS credentials or root account.

### Create a dedicated IAM user for CI/CD

```bash
aws iam create-user --user-name skynet-cicd
```

### Attach this inline policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAuth",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "ECRPush",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "arn:aws:ecr:ap-south-1:*:repository/skynet-ops-audit-service"
    },
    {
      "Sid": "ECSDeployOnly",
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices"
      ],
      "Resource": "arn:aws:ecs:ap-south-1:*:service/skynet-ops-audit-service-cluster/skynet-ops-audit-service-service"
    }
  ]
}
```

```bash
# Save the above as cicd-policy.json then attach it
aws iam put-user-policy \
  --user-name skynet-cicd \
  --policy-name skynet-cicd-policy \
  --policy-document file://cicd-policy.json

# Create access keys for GitHub Secrets
aws iam create-access-key --user-name skynet-cicd
```

Add the output `AccessKeyId` and `SecretAccessKey` to GitHub:
`Settings → Secrets and variables → Actions`

| Secret name | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | AccessKeyId from above |
| `AWS_SECRET_ACCESS_KEY` | SecretAccessKey from above |

### What this CI/CD user cannot do
- Cannot read or write SSM parameters — secrets are safe
- Cannot modify ECS task definitions or IAM roles
- Cannot access EFS directly
- Cannot create or delete any AWS resources
- Scoped to this specific ECR repo and ECS service only

---

## What We Would Add in Production

| Security Control          | Current Status | Production Recommendation              |
|---------------------------|----------------|----------------------------------------|
| HTTPS / TLS               | ❌ HTTP only   | ACM certificate + ALB HTTPS listener   |
| API Authentication        | ⚠️ Optional   | Enforce `API_KEY` for all requests     |
| VPC private subnets       | ⚠️ Public      | Move ECS to private subnets + NAT GW   |
| WAF                       | ❌ None        | AWS WAF on ALB for rate limiting       |
| Secrets rotation          | ❌ Manual      | AWS Secrets Manager with auto-rotation |
| Container image signing   | ❌ None        | AWS Signer for image verification      |

These are intentionally deferred for pilot scale to keep costs within $25-75/month.
