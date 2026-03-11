# ── ECR Repository ────────────────────────────────────────────────────────────
resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # security — scans image for vulnerabilities
  }

  tags = { Name = var.app_name }
}

# Auto delete old images — keeps registry storage costs low
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only last 3 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = { type = "expire" }
    }]
  })
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = var.log_retention_days # 7 days for dev/pilot — cost control

  tags = { Name = "${var.app_name}-logs" }
}

# ── IAM Role for ECS Task Execution ──────────────────────────────────────────
resource "aws_iam_role" "ecs_execution" {
  name = "${var.app_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow ECS to read SSM secrets
resource "aws_iam_role_policy" "ssm_read" {
  name = "${var.app_name}-ssm-read"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters", "ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.app_name}/*"
    }]
  })
}

# ── IAM Role for ECS Task (runtime permissions) ───────────────────────────────
resource "aws_iam_role" "ecs_task" {
  name = "${var.app_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Allow ECS task to access EFS
resource "aws_iam_role_policy" "efs_access" {
  name = "${var.app_name}-efs-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess"
      ]
      Resource = aws_efs_file_system.data.arn
    }]
  })
}

# ── SSM Parameter for API Key (secrets management) ────────────────────────────
resource "aws_ssm_parameter" "api_key" {
  name        = "/${var.app_name}/API_KEY"
  type        = "SecureString"
  value       = "http://skynet-ops-audit-service-alb-1824300216.ap-south-1.elb.amazonaws.com"
  description = "Optional API key for skynet-ops-audit-service"

  lifecycle {
    ignore_changes = [value]
  }
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled" # better metrics in CloudWatch
  }

  tags = { Name = "${var.app_name}-cluster" }
}

# ── ECS Task Definition ───────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "app" {
  family                   = var.app_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu    # 256 = 0.25 vCPU
  memory                   = var.container_memory # 512 MB
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  # EFS volume definition
  volume {
    name = "efs-data"

    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.data.id
      transit_encryption      = "ENABLED" # encrypt data in transit
      authorization_config {
        access_point_id = aws_efs_access_point.data.id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([{
    name      = var.app_name
    image     = var.image_uri
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    # Mount EFS into the container at /app/data
    mountPoints = [{
      sourceVolume  = "efs-data"
      containerPath = "/app/data"
      readOnly      = false
    }]

    environment = [
      { name = "APP_ENV",              value = var.environment },
      { name = "PORT",                 value = tostring(var.container_port) },
      { name = "LOG_LEVEL",            value = "info" },
      { name = "STORE_BACKEND",        value = "sqlite" },
      { name = "DB_URL",               value = "/app/data/events.db" },
      { name = "METRICS_DEMO_ENABLED", value = "true" },
      { name = "MAX_EVENTS_LIMIT",     value = "100" }
    ]

    secrets = [{
      name      = "API_KEY"
      valueFrom = aws_ssm_parameter.api_key.arn
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${var.container_port}/health')\""]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }
  }])
}

# ── ECS Service ───────────────────────────────────────────────────────────────
resource "aws_ecs_service" "app" {
  name            = "${var.app_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.app_name
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [desired_count] # allow manual scaling without terraform drift
  }
}
