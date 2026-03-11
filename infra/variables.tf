variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1" # Mumbai — closest for India
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "skynet-ops-audit-service"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8000
}

variable "container_cpu" {
  description = "Fargate CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256 # smallest size = cheapest
}

variable "container_memory" {
  description = "Fargate memory in MB"
  type        = number
  default     = 512 # smallest size = cheapest
}

variable "desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 1 # pilot scale, 1 is enough
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7 # keep costs low for dev/pilot
}

variable "monthly_budget_usd" {
  description = "Monthly budget alert threshold in USD"
  type        = number
  default     = 50
}

variable "image_uri" {
  description = "Full ECR image URI e.g. 123456789.dkr.ecr.ap-south-1.amazonaws.com/skynet-ops-audit-service:latest"
  type        = string
}
