# Terraform Variables for Development Environment
# Shares the same AWS account as prod but uses separate resources (different
# environment prefix → separate ECS cluster, ALB, SQS queue, S3 bucket, etc.)
#
# Usage:
#   make plan  ENVIRONMENT=dev
#   make apply ENVIRONMENT=dev
#
# Image tag is auto-updated by the app main pipeline when enable_dev_auto_update = true.

# ==========================================
# General Configuration
# ==========================================
aws_region   = "us-east-2"
project_name = "exam-costa"
environment  = "dev"

tags = {
  Project     = "DevOps Exam Costa"
  Environment = "dev"
  ManagedBy   = "terraform"
  Owner       = "costa"
  Purpose     = "exam-dev"
  CostCenter  = "devops-exam"
}

# ==========================================
# Network Configuration
# ==========================================
vpc_cidr             = "10.2.0.0/16" # Separate CIDR from prod (10.1.0.0/16)
availability_zones   = ["us-east-2a", "us-east-2b"]
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24"]

enable_nat_gateway = true
single_nat_gateway = true # Single NAT to save cost in dev

enable_s3_endpoint         = true  # Free — always on
enable_interface_endpoints = false # Not needed in dev

# ==========================================
# ECR Configuration
# ==========================================
create_ecr_repositories  = false # ECR repos shared with prod (created by bootstrap)
ecr_image_tag_mutability = "MUTABLE"
ecr_scan_on_push         = true

# Image tag — updated automatically by app main pipeline when enable_dev_auto_update = true
image_tag = "latest"

# ==========================================
# S3 Configuration
# ==========================================
s3_force_destroy     = true  # Allow easy cleanup in dev
s3_lifecycle_enabled = false # No lifecycle rules needed in dev

# ==========================================
# SQS Configuration
# ==========================================
sqs_visibility_timeout = 30
sqs_message_retention  = 86400 # 1 day in dev
sqs_receive_wait_time  = 20
sqs_max_receive_count  = 5

# ==========================================
# SSM Configuration
# ==========================================
api_token_value = "dev-test-token"

# ==========================================
# ALB Configuration
# ==========================================
alb_enable_deletion_protection = false # Allow easy teardown in dev
alb_idle_timeout               = 60

# ==========================================
# ECS Configuration — smaller sizes for dev
# ==========================================
ecs_enable_container_insights = false # Save cost in dev

api_desired_count = 1   # Single instance in dev
api_cpu           = 256 # 0.25 vCPU
api_memory        = 512 # 512 MB

worker_desired_count = 1
worker_cpu           = 256
worker_memory        = 512
worker_poll_interval = 10

# ==========================================
# Logging / Monitoring
# ==========================================
log_retention_days      = 7     # Shorter retention in dev
enable_alarms           = false # No alarms in dev
enable_pipeline_metrics = false

# ==========================================
# CI/CD Configuration (shared roles from bootstrap)
# ==========================================
enable_cicd           = false # Dev env doesn't need its own pipelines
codecommit_repo_name  = "exam-costa-infra"
codebuild_role_arn    = "arn:aws:iam::214422569286:role/exam-costa-codebuild-role"
codepipeline_role_arn = "arn:aws:iam::214422569286:role/exam-costa-codepipeline-role"
artifact_bucket_name  = "exam-costa-pipeline-artifacts"
eventbridge_role_arn  = "arn:aws:iam::214422569286:role/exam-costa-eventbridge-pipeline-role"

# App pipeline — disabled for dev env (app pipelines live in prod env config)
enable_app_pipeline          = false
enable_dev_auto_update       = false
enable_ecr_enhanced_scanning = false
