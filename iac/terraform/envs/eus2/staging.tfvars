# Terraform Variables for Staging Environment
# Staging is the main branch deployment target.
# GitHub Actions deploys here on every push to main.
#
# Usage:
#   terraform plan  -var-file=staging.tfvars -var-file=image_tags.staging.tfvars
#   terraform apply -var-file=staging.tfvars -var-file=image_tags.staging.tfvars

# ==========================================
# General Configuration
# ==========================================
aws_region   = "us-east-2"
project_name = "exam-costa"
environment  = "staging"

tags = {
  Project     = "DevOps Exam Costa"
  Environment = "staging"
  ManagedBy   = "terraform"
  Owner       = "costa"
  Purpose     = "exam-staging"
  CostCenter  = "devops-exam"
}

# ==========================================
# Network Configuration
# ==========================================
vpc_cidr             = "10.2.0.0/16"
availability_zones   = ["us-east-2a", "us-east-2b"]
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24"]

enable_nat_gateway = true
single_nat_gateway = true # Single NAT to save cost in staging

enable_s3_endpoint         = true  # Free — always on
enable_interface_endpoints = false # Not needed in staging

# ==========================================
# ECR Configuration
# ==========================================
create_ecr_repositories  = false # ECR repos shared (created by bootstrap)
ecr_image_tag_mutability = "MUTABLE"
ecr_scan_on_push         = true

# Image tag — managed by GitHub Actions via image_tags.staging.tfvars
image_tag = "latest"

# ==========================================
# S3 Configuration
# ==========================================
s3_force_destroy       = true  # Allow easy cleanup in staging
s3_versioning_enabled  = false # No versioning needed in staging
s3_block_public_access = false # Disabled — account SCP denies PutBucketPublicAccessBlock
s3_lifecycle_enabled   = false # No lifecycle rules needed in staging

# ==========================================
# SQS Configuration
# ==========================================
sqs_visibility_timeout = 30
sqs_message_retention  = 86400 # 1 day in staging
sqs_receive_wait_time  = 20
sqs_max_receive_count  = 5

# API token at /{project_name}/{env}/api/token is created by `make bootstrap`

# ==========================================
# ALB Configuration
# ==========================================
alb_enable_deletion_protection = false # Allow easy teardown in staging
alb_idle_timeout               = 60

# ==========================================
# ECS Configuration — smaller sizes for staging
# ==========================================
ecs_enable_container_insights = true

api_desired_count = 1   # Single instance in staging
api_cpu           = 256 # 0.25 vCPU
api_memory        = 512 # 512 MB

worker_desired_count = 1
worker_cpu           = 256
worker_memory        = 512
worker_poll_interval = 10
log_level            = "INFO"

# ==========================================
# Logging / Monitoring
# ==========================================
log_retention_days           = 7
enable_cloudwatch_monitoring = true
enable_alarms                = true
enable_pipeline_metrics      = false

# ==========================================
# CI/CD Configuration
# ==========================================
enable_cicd           = false # Staging env uses GitHub Actions, not CodePipeline
codecommit_repo_name  = "exam-costa-infra"
codebuild_role_arn    = "arn:aws:iam::214422569286:role/exam-costa-codebuild-role"
codepipeline_role_arn = "arn:aws:iam::214422569286:role/exam-costa-codepipeline-role"
artifact_bucket_name  = "exam-costa-pipeline-artifacts"
eventbridge_role_arn  = "arn:aws:iam::214422569286:role/exam-costa-eventbridge-pipeline-role"

enable_app_pipeline          = false
enable_dev_auto_update       = false
enable_ecr_enhanced_scanning = false
