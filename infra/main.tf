terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — create this S3 bucket manually once before terraform init
  # or comment out and use local state for dev
  # backend "s3" {
  #   bucket = "skynet-tfstate-<your-account-id>"
  #   key    = "skynet-ops-audit-service/terraform.tfstate"
  #   region = "ap-south-1"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "skynet-ops-audit-service"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
