# Terraform Variables for Production Environment
# Copy this file to prod.tfvars and customize values
# cp prod.tfvars.example prod.tfvars

# ==========================================
# General Configuration
# ==========================================
aws_region   = "us-east-2"
project_name = "exam-costa"
environment  = "prod"

tags = {
  Project     = "DevOps Exam Costa"
  Environment = "prod"
  ManagedBy   = "terraform"
  Owner       = "costa"
  Purpose     = "exam-submission"
  CostCenter  = "devops-exam"
}

# ==========================================
# Network Configuration
# ==========================================
vpc_cidr             = "10.1.0.0/16" # Different CIDR for prod
availability_zones   = ["us-east-2a", "us-east-2b"]
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]

enable_nat_gateway         = true
single_nat_gateway         = true  # Single NAT to minimise cost
enable_s3_endpoint         = true  # Free — always on
enable_interface_endpoints = false # ~$7/mo each — enable for full private networking

# ==========================================
# ECR Configuration
# ==========================================
create_ecr_repositories  = false       # ECR repos created by bootstrap
ecr_image_tag_mutability = "IMMUTABLE" # Immutable tags for prod
ecr_scan_on_push         = true

# Image configuration - use specific version tags
image_tag = "v1.0.0" # MUST be set via CI/CD with semver tag
# api_image = ""      # Leave empty to use ECR
# worker_image = ""   # Leave empty to use ECR

# ==========================================
# S3 Configuration
# ==========================================
s3_force_destroy     = false # Protect data in prod
s3_lifecycle_enabled = true  # Enable lifecycle rules

# ==========================================
# SQS Configuration
# ==========================================
sqs_visibility_timeout = 30
sqs_message_retention  = 1209600 # 14 days in prod
sqs_receive_wait_time  = 20      # Long polling
sqs_max_receive_count  = 3       # Lower threshold for prod

# ==========================================
# SSM Configuration
# ==========================================
# API token - MUST be changed after deployment!
api_token_value = "CHANGE_ME_IN_SSM_AFTER_DEPLOYMENT"

# ==========================================
# ALB Configuration
# ==========================================
alb_enable_deletion_protection = false # Disabled for exam — easy teardown
alb_idle_timeout               = 60

# ==========================================
# ECS Configuration
# ==========================================
ecs_enable_container_insights = true

api_desired_count = 1   # Minimum for exam
api_cpu           = 256 # 0.25 vCPU
api_memory        = 512 # 512 MB

worker_desired_count = 1
worker_cpu           = 256
worker_memory        = 512
worker_poll_interval = 10 # Poll every 10 seconds
log_level            = "WARNING"

# ==========================================
# Logging Configuration
# ==========================================
log_retention_days = 30 # Keep logs for 30 days in prod

# ==========================================
# Monitoring Configuration
# ==========================================
enable_cloudwatch_monitoring = true
enable_alarms                = true
enable_pipeline_metrics      = false # No CodeBuild pipelines — using GitHub Actions

# ==========================================
# CI/CD Configuration (from bootstrap outputs)
# ==========================================
enable_cicd           = false # Using GitHub Actions, not CodePipeline/CodeBuild
codecommit_repo_name  = "exam-costa-infra"
codebuild_role_arn    = "arn:aws:iam::214422569286:role/exam-costa-codebuild-role"
codepipeline_role_arn = "arn:aws:iam::214422569286:role/exam-costa-codepipeline-role"
artifact_bucket_name  = "exam-costa-pipeline-artifacts"
eventbridge_role_arn  = "arn:aws:iam::214422569286:role/exam-costa-eventbridge-pipeline-role"

# ==========================================
# App Pipeline Configuration
# ==========================================
# Enable after app CodeCommit repo is seeded (make bootstrap creates the repo)
enable_app_pipeline      = false # set to true once exam-costa-app repo has code
infra_repo_name          = "exam-costa-infra"
app_codecommit_repo_name = "exam-costa-app"

# Auto-update dev.tfvars image_tag when app main branch builds
enable_dev_auto_update = false # set to true once dev env is deployed

# AWS Inspector enhanced scanning (per-image cost — see Inspector pricing)
enable_ecr_enhanced_scanning = false

# ==========================================
# Production Deployment Notes:
# ==========================================
# 1. Always deploy with specific semver tags (e.g., v1.0.0, v1.0.1)
# 2. Change API token in SSM Parameter Store after deployment
# 3. Review and test plan before applying
# 4. Enable CloudWatch alarms and configure SNS notifications
# 5. Consider adding WAF for ALB
# 6. Set up backup policies for S3 bucket
# 7. Configure budget alerts
# 8. Review IAM permissions and follow principle of least privilege
