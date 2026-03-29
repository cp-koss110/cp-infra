# Environment Variables for US-East-2 (eus2)

# ==========================================
# General Configuration
# ==========================================
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "exam-costa"
}

variable "environment" {
  description = "Environment name (test, staging, production, dev)"
  type        = string

  validation {
    condition     = contains(["test", "staging", "production", "dev"], var.environment)
    error_message = "environment must be one of: test, staging, production, dev"
  }
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

# ==========================================
# Network Configuration
# ==========================================
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "enable_s3_endpoint" {
  description = "Enable S3 Gateway VPC endpoint (free — routes S3 traffic inside AWS, bypasses NAT)"
  type        = bool
  default     = true
}

# Interface endpoints cost ~$0.01/hr each (~$7/month per endpoint).
# Enable to keep SQS, SSM, ECR, and CloudWatch Logs traffic fully private without NAT.
variable "enable_interface_endpoints" {
  description = "Enable Interface VPC endpoints for SQS, SSM, ECR, and CloudWatch Logs"
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway (cost optimization)"
  type        = bool
  default     = true
}

# ==========================================
# ECR Configuration
# ==========================================
variable "create_ecr_repositories" {
  description = "Create ECR repositories for images"
  type        = bool
  default     = true
}

variable "ecr_image_tag_mutability" {
  description = "ECR image tag mutability"
  type        = string
  default     = "MUTABLE"
}

variable "ecr_scan_on_push" {
  description = "Enable ECR image scanning on push"
  type        = bool
  default     = true
}

variable "api_image" {
  description = "API Docker image (override if using external registry)"
  type        = string
  default     = ""
}

variable "worker_image" {
  description = "Worker Docker image (override if using external registry)"
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "Docker image tag to deploy (fallback for both api and worker)"
  type        = string
  default     = "latest"
}

variable "api_image_tag" {
  description = "API Docker image tag (overrides image_tag when set)"
  type        = string
  default     = ""
}

variable "worker_image_tag" {
  description = "Worker Docker image tag (overrides image_tag when set)"
  type        = string
  default     = ""
}

# ==========================================
# S3 Configuration
# ==========================================
variable "s3_force_destroy" {
  description = "Allow destroying S3 bucket with objects (USE WITH CAUTION)"
  type        = bool
  default     = false
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle rules"
  type        = bool
  default     = true
}

variable "s3_versioning_enabled" {
  description = "Enable versioning on the messages S3 bucket"
  type        = bool
  default     = false
}

variable "s3_block_public_access" {
  description = "Block all public access on the messages S3 bucket. Disable if the account SCP denies s3:PutBucketPublicAccessBlock."
  type        = bool
  default     = false
}

# ==========================================
# SQS Configuration
# ==========================================
variable "sqs_visibility_timeout" {
  description = "SQS visibility timeout in seconds"
  type        = number
  default     = 30
}

variable "sqs_message_retention" {
  description = "SQS message retention in seconds"
  type        = number
  default     = 345600 # 4 days
}

variable "sqs_receive_wait_time" {
  description = "SQS long polling wait time in seconds"
  type        = number
  default     = 20
}

variable "sqs_max_receive_count" {
  description = "Max receive count before sending to DLQ"
  type        = number
  default     = 5
}

# ==========================================
# ALB Configuration
# ==========================================
variable "alb_enable_deletion_protection" {
  description = "Enable ALB deletion protection"
  type        = bool
  default     = false
}

variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 60
}

# ==========================================
# ECS Configuration
# ==========================================
variable "ecs_enable_container_insights" {
  description = "Enable ECS Container Insights"
  type        = bool
  default     = true
}

# API Service Configuration
variable "api_desired_count" {
  description = "Desired number of API tasks"
  type        = number
  default     = 1
}

variable "api_cpu" {
  description = "API task CPU units"
  type        = number
  default     = 256
}

variable "api_memory" {
  description = "API task memory in MB"
  type        = number
  default     = 512
}

# Worker Service Configuration
variable "worker_desired_count" {
  description = "Desired number of Worker tasks"
  type        = number
  default     = 1
}

variable "worker_cpu" {
  description = "Worker task CPU units"
  type        = number
  default     = 256
}

variable "worker_memory" {
  description = "Worker task memory in MB"
  type        = number
  default     = 512
}

variable "worker_poll_interval" {
  description = "Worker polling interval in seconds"
  type        = number
  default     = 5
}

variable "log_level" {
  description = "Log level for API and Worker services (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "log_level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL"
  }
}

# ==========================================
# Logging Configuration
# ==========================================
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

# ==========================================
# Monitoring Configuration
# ==========================================
variable "enable_cloudwatch_monitoring" {
  description = "Master toggle: enable CloudWatch dashboard, alarms, and Container Insights"
  type        = bool
  default     = true
}

variable "enable_alarms" {
  description = "Enable CloudWatch alarms (overridden to true when enable_cloudwatch_monitoring = true)"
  type        = bool
  default     = true
}

# ==========================================
# CI/CD Configuration
# ==========================================
variable "enable_cicd" {
  description = "Create CodeBuild projects and CodePipeline pipelines"
  type        = bool
  default     = false
}

variable "codecommit_repo_name" {
  description = "Name of the CodeCommit repository (created by bootstrap)"
  type        = string
  default     = "exam-costa"
}

variable "codebuild_role_arn" {
  description = "IAM role ARN for CodeBuild (output from bootstrap)"
  type        = string
  default     = ""
}

variable "codepipeline_role_arn" {
  description = "IAM role ARN for CodePipeline (output from bootstrap)"
  type        = string
  default     = ""
}

variable "artifact_bucket_name" {
  description = "S3 bucket name for CodePipeline artifacts (output from bootstrap)"
  type        = string
  default     = ""
}

variable "eventbridge_role_arn" {
  description = "IAM role ARN for EventBridge to trigger pipelines (output from bootstrap)"
  type        = string
  default     = ""
}

variable "tf_backend_bucket" {
  description = "S3 bucket name used by Terraform backend (passed to CodeBuild as env var)"
  type        = string
  default     = "exam-costa-terraform-state"
}

variable "tf_lock_table" {
  description = "DynamoDB table name for Terraform locking (passed to CodeBuild as env var)"
  type        = string
  default     = "exam-costa-terraform-locks"
}

variable "enable_pipeline_metrics" {
  description = "Emit build success/failure metrics to CloudWatch and create alarms"
  type        = bool
  default     = true
}

# ==========================================
# App Pipeline (application repo CI/CD)
# ==========================================
variable "enable_app_pipeline" {
  description = "Create CI/CD pipelines for the application repo (branch, main, tag)"
  type        = bool
  default     = false
}

variable "app_codecommit_repo_name" {
  description = "Name of the application CodeCommit repository"
  type        = string
  default     = "exam-costa-app"
}

variable "infra_repo_name" {
  description = "Name of the infra CodeCommit repository (app pipelines commit image tags here)"
  type        = string
  default     = "exam-costa-infra"
}

# When true, the app main-branch pipeline commits the new image tag to dev.tfvars
# in the infra repo, which triggers the infra CI plan for dev.
variable "enable_dev_auto_update" {
  description = "App main pipeline auto-updates dev.tfvars image_tag in the infra repo"
  type        = bool
  default     = false
}

# AWS ECR Enhanced Scanning uses Amazon Inspector for deeper vulnerability analysis.
# Cost: per-image scan fee. See https://aws.amazon.com/inspector/pricing/
# Requires Inspector to be enabled in the account.
variable "enable_ecr_enhanced_scanning" {
  description = "Enable ECR Enhanced Scanning (Amazon Inspector) for container images"
  type        = bool
  default     = false
}

variable "github_owner" {
  description = "GitHub organisation or user that owns the service repos (used to build metric dimension values for GitHub/Actions CloudWatch widgets)"
  type        = string
  default     = "koss110"
}
