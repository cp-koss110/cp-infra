terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    # Configuration loaded from backend.hcl file
    # Run: terraform init -backend-config=backend.hcl
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      var.tags,
      {
        Project     = var.project_name
        Environment = var.environment
        ManagedBy   = "terraform"
      }
    )
  }
}

# ==========================================
# Local Variables
# ==========================================
locals {
  project_prefix = "${var.project_name}-${var.environment}"

  # Per-service image tag resolution: use service-specific tag if set, else fall back to image_tag
  resolved_api_tag    = var.api_image_tag != "" ? var.api_image_tag : var.image_tag
  resolved_worker_tag = var.worker_image_tag != "" ? var.worker_image_tag : var.image_tag

  # ECR repository URLs — three resolution paths (in priority order):
  # 1. Explicit var override  2. ECR created by this layer  3. ECR created by bootstrap
  api_image = var.api_image != "" ? var.api_image : (
    length(module.ecr_api) > 0 ?
    "${module.ecr_api[0].repository_url}:${local.resolved_api_tag}" :
    length(data.aws_ecr_repository.api) > 0 ?
    "${data.aws_ecr_repository.api[0].repository_url}:${local.resolved_api_tag}" :
    "nginx:latest"
  )

  worker_image = var.worker_image != "" ? var.worker_image : (
    length(module.ecr_worker) > 0 ?
    "${module.ecr_worker[0].repository_url}:${local.resolved_worker_tag}" :
    length(data.aws_ecr_repository.worker) > 0 ?
    "${data.aws_ecr_repository.worker[0].repository_url}:${local.resolved_worker_tag}" :
    "nginx:latest"
  )

  # ECR repo names used as CodeBuild env vars
  ecr_api_repo_name    = "${var.project_name}-api"
  ecr_worker_repo_name = "${var.project_name}-worker"
}

# ==========================================
# Networking
# ==========================================
module "network" {
  source = "../../modules/network"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr

  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  enable_s3_endpoint         = var.enable_s3_endpoint
  enable_interface_endpoints = var.enable_interface_endpoints

  tags = var.tags
}

# ==========================================
# ECR Repositories
# ==========================================
module "ecr_api" {
  source = "../../modules/ecr"
  count  = var.create_ecr_repositories ? 1 : 0

  repository_name = "${local.project_prefix}-api"

  image_tag_mutability = var.ecr_image_tag_mutability
  scan_on_push         = var.ecr_scan_on_push

  lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })

  tags = var.tags
}

module "ecr_worker" {
  source = "../../modules/ecr"
  count  = var.create_ecr_repositories ? 1 : 0

  repository_name = "${local.project_prefix}-worker"

  image_tag_mutability = var.ecr_image_tag_mutability
  scan_on_push         = var.ecr_scan_on_push

  lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })

  tags = var.tags
}

# ==========================================
# S3 Bucket for Messages
# ==========================================
module "s3_messages" {
  source = "../../modules/s3"

  bucket_name   = "${local.project_prefix}-messages-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.s3_force_destroy

  versioning_enabled  = var.s3_versioning_enabled
  block_public_access = var.s3_block_public_access
  lifecycle_enabled   = var.s3_lifecycle_enabled

  lifecycle_rules = var.s3_lifecycle_enabled ? [
    {
      id      = "transition-old-messages"
      enabled = true

      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]

      expiration_days = 365
    }
  ] : []

  tags = var.tags
}

# ==========================================
# SQS Queue with DLQ
# ==========================================
module "sqs_messages" {
  source = "../../modules/sqs"

  queue_name = "${local.project_prefix}-messages"

  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention
  receive_wait_time_seconds  = var.sqs_receive_wait_time

  create_dlq        = true
  max_receive_count = var.sqs_max_receive_count

  tags = var.tags
}

# ==========================================
# IAM Roles
# ==========================================

# ECS Task Execution Role
module "iam_ecs_execution_role" {
  source = "../../modules/iam"

  role_name        = "${local.project_prefix}-ecs-execution-role"
  role_description = "ECS task execution role for ${var.project_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]

  tags = var.tags
}

# API Service Task Role
module "iam_api_task_role" {
  source = "../../modules/iam"

  role_name        = "${local.project_prefix}-api-task-role"
  role_description = "IAM role for API service tasks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  inline_policies = {
    ssm_access = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
      }]
    })

    sqs_send = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = module.sqs_messages.queue_arn
      }]
    })
  }

  tags = var.tags
}

# Worker Service Task Role
module "iam_worker_task_role" {
  source = "../../modules/iam"

  role_name        = "${local.project_prefix}-worker-task-role"
  role_description = "IAM role for Worker service tasks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  inline_policies = {
    sqs_receive = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = module.sqs_messages.queue_arn
      }]
    })

    s3_upload = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${module.s3_messages.bucket_arn}/*"
      }]
    })
  }

  tags = var.tags
}

# ==========================================
# SSM Parameter for API Token
# ==========================================
# Token is created by `make bootstrap` — Terraform reads it as a data source.
# This prevents `terraform destroy` on one environment from deleting the shared secret.
data "aws_ssm_parameter" "api_token" {
  name = "/${var.project_name}/${var.environment}/api/token"
}

# ==========================================
# Application Load Balancer
# ==========================================
module "alb" {
  source = "../../modules/alb"

  name = "${local.project_prefix}-alb"

  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.public_subnet_ids
  security_groups = [aws_security_group.alb.id]

  # Target group for API service
  target_port = 8000
  target_type = "ip"

  enable_deletion_protection = var.alb_enable_deletion_protection
  idle_timeout               = var.alb_idle_timeout

  # HTTPS — self-signed cert imported into ACM (no custom domain required)
  certificate_arn       = aws_acm_certificate.self_signed.arn
  enable_https_redirect = true

  # Health check for API /healthz endpoint
  health_check_path    = "/healthz"
  health_check_matcher = "200"

  tags = var.tags
}

# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${local.project_prefix}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = module.network.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${local.project_prefix}-alb-sg"
  })
}

# ==========================================
# Self-signed TLS certificate → ACM
# No custom domain is available, so a self-signed cert is generated by
# Terraform and imported into ACM. HTTPS works end-to-end; clients will
# receive an untrusted-cert warning (expected for *.elb.amazonaws.com).
# Replace with a proper ACM-issued cert once a domain is available.
# ==========================================
resource "tls_private_key" "self_signed" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  private_key_pem = tls_private_key.self_signed.private_key_pem

  subject {
    common_name  = "${local.project_prefix}.internal"
    organization = var.project_name
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "self_signed" {
  private_key      = tls_private_key.self_signed.private_key_pem
  certificate_body = tls_self_signed_cert.self_signed.cert_pem

  tags = merge(var.tags, {
    Name = "${local.project_prefix}-self-signed-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for API Service
resource "aws_security_group" "api_service" {
  name        = "${local.project_prefix}-api-service-sg"
  description = "Security group for API service"
  vpc_id      = module.network.vpc_id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Allow traffic from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${local.project_prefix}-api-service-sg"
  })
}

# Security Group for Worker Service
resource "aws_security_group" "worker_service" {
  name        = "${local.project_prefix}-worker-service-sg"
  description = "Security group for Worker service"
  vpc_id      = module.network.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, {
    Name = "${local.project_prefix}-worker-service-sg"
  })
}

# ==========================================
# ECS Cluster
# ==========================================
module "ecs_cluster" {
  source = "../../modules/ecs_cluster"

  cluster_name = "${local.project_prefix}-cluster"

  enable_container_insights = var.ecs_enable_container_insights

  tags = var.tags
}

# ==========================================
# ECS Service - API
# ==========================================
module "ecs_service_api" {
  source = "../../modules/ecs_service"

  service_name  = "${local.project_prefix}-api"
  cluster_id    = module.ecs_cluster.cluster_id
  desired_count = var.api_desired_count

  # Task Definition
  container_name  = "api"
  container_image = local.api_image
  container_port  = 8000

  cpu    = var.api_cpu
  memory = var.api_memory

  # Networking
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  security_groups = [aws_security_group.api_service.id]

  # IAM
  execution_role_arn = module.iam_ecs_execution_role.role_arn
  task_role_arn      = module.iam_api_task_role.role_arn

  # Load Balancer
  target_group_arn = module.alb.target_group_arn

  # Environment Variables
  environment_variables = {
    ENVIRONMENT        = var.environment
    AWS_REGION         = var.aws_region
    SQS_QUEUE_URL      = module.sqs_messages.queue_url
    SSM_PARAMETER_NAME = data.aws_ssm_parameter.api_token.name
    LOG_LEVEL          = var.log_level
  }

  # CloudWatch Logs
  log_retention_days = var.log_retention_days
  aws_region         = var.aws_region

  # Grace period for ALB health checks to pass before marking unhealthy
  health_check_grace_period_seconds = 60

  tags = var.tags
}

# ==========================================
# ECS Service - Worker
# ==========================================
module "ecs_service_worker" {
  source = "../../modules/ecs_service"

  service_name  = "${local.project_prefix}-worker"
  cluster_id    = module.ecs_cluster.cluster_id
  desired_count = var.worker_desired_count

  # Task Definition
  container_name  = "worker"
  container_image = local.worker_image
  container_port  = 0 # No port exposure needed

  cpu    = var.worker_cpu
  memory = var.worker_memory

  # Networking
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  security_groups = [aws_security_group.worker_service.id]

  # IAM
  execution_role_arn = module.iam_ecs_execution_role.role_arn
  task_role_arn      = module.iam_worker_task_role.role_arn

  # No Load Balancer for worker
  target_group_arn = null

  # Environment Variables
  environment_variables = {
    ENVIRONMENT    = var.environment
    AWS_REGION     = var.aws_region
    SQS_QUEUE_URL  = module.sqs_messages.queue_url
    S3_BUCKET_NAME = module.s3_messages.bucket_name
    POLL_INTERVAL  = tostring(var.worker_poll_interval)
    LOG_LEVEL      = var.log_level
  }

  # CloudWatch Logs
  log_retention_days = var.log_retention_days
  aws_region         = var.aws_region

  # No health check for worker
  health_check_grace_period_seconds = 0

  tags = var.tags
}

# ==========================================
# CloudWatch Alarms (Optional)
# ==========================================
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${local.project_prefix}-alb-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Alert when ALB has unhealthy targets"

  dimensions = {
    TargetGroup  = module.alb.target_group_arn_suffix
    LoadBalancer = module.alb.load_balancer_arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "pipeline_api_build_failed" {
  count = var.enable_pipeline_metrics ? 1 : 0

  alarm_name          = "${local.project_prefix}-pipeline-api-build-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BuildSuccess"
  namespace           = "ExamCosta/CICD"
  period              = 300
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_description   = "Alert when the API build/test pipeline fails"

  dimensions = {
    Service     = "api"
    Environment = var.environment
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "pipeline_worker_build_failed" {
  count = var.enable_pipeline_metrics ? 1 : 0

  alarm_name          = "${local.project_prefix}-pipeline-worker-build-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BuildSuccess"
  namespace           = "ExamCosta/CICD"
  period              = 300
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_description   = "Alert when the Worker build/test pipeline fails"

  dimensions = {
    Service     = "worker"
    Environment = var.environment
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${local.project_prefix}-sqs-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000
  alarm_description   = "Alert when SQS queue has too many messages"

  dimensions = {
    QueueName = module.sqs_messages.queue_name
  }

  tags = var.tags
}

# ==========================================
# CloudWatch Dashboard
# ==========================================
resource "aws_cloudwatch_dashboard" "main" {
  count          = var.enable_cloudwatch_monitoring ? 1 : 0
  dashboard_name = local.project_prefix

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ECS CPU Utilization (%)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", module.ecs_cluster.cluster_name, "ServiceName", module.ecs_service_api.service_name, { label = "api" }],
            ["AWS/ECS", "CPUUtilization", "ClusterName", module.ecs_cluster.cluster_name, "ServiceName", module.ecs_service_worker.service_name, { label = "worker" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ECS Memory Utilization (%)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", module.ecs_cluster.cluster_name, "ServiceName", module.ecs_service_api.service_name, { label = "api" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", module.ecs_cluster.cluster_name, "ServiceName", module.ecs_service_worker.service_name, { label = "worker" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", module.alb.load_balancer_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "ALB 5xx Errors"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.alb.load_balancer_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "SQS Messages Visible"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", module.sqs_messages.queue_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "SQS Messages Sent vs Deleted"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", module.sqs_messages.queue_name, { label = "sent" }],
            ["AWS/SQS", "NumberOfMessagesDeleted", "QueueName", module.sqs_messages.queue_name, { label = "deleted (processed)" }]
          ]
        }
      },
      # ---- GitHub Actions ----
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "GitHub Actions — Workflow Runs"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["GitHub/Actions", "WorkflowRun", "Repository", "${var.github_owner}/cp-api", "Workflow", "CI", { label = "cp-api / CI" }],
            ["GitHub/Actions", "WorkflowRun", "Repository", "${var.github_owner}/cp-api", "Workflow", "Release", { label = "cp-api / Release" }],
            ["GitHub/Actions", "WorkflowRun", "Repository", "${var.github_owner}/cp-worker", "Workflow", "CI", { label = "cp-worker / CI" }],
            ["GitHub/Actions", "WorkflowRun", "Repository", "${var.github_owner}/cp-worker", "Workflow", "Release", { label = "cp-worker / Release" }],
            ["GitHub/Actions", "WorkflowRun", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Staging Deploy", { label = "cp-infra / Staging Deploy" }],
            ["GitHub/Actions", "WorkflowRun", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Production Deploy", { label = "cp-infra / Production Deploy" }],
            ["GitHub/Actions", "WorkflowRun", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Staging PR Checks", { label = "cp-infra / Staging PR Checks" }],
            ["GitHub/Actions", "WorkflowRun", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Production PR Checks", { label = "cp-infra / Production PR Checks" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "GitHub Actions — Success Rate"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          yAxis  = { left = { min = 0, max = 1 } }
          metrics = [
            ["GitHub/Actions", "WorkflowSuccess", "Repository", "${var.github_owner}/cp-api", "Workflow", "CI", { label = "cp-api / CI" }],
            ["GitHub/Actions", "WorkflowSuccess", "Repository", "${var.github_owner}/cp-api", "Workflow", "Release", { label = "cp-api / Release" }],
            ["GitHub/Actions", "WorkflowSuccess", "Repository", "${var.github_owner}/cp-worker", "Workflow", "CI", { label = "cp-worker / CI" }],
            ["GitHub/Actions", "WorkflowSuccess", "Repository", "${var.github_owner}/cp-worker", "Workflow", "Release", { label = "cp-worker / Release" }],
            ["GitHub/Actions", "WorkflowSuccess", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Staging Deploy", { label = "cp-infra / Staging Deploy" }],
            ["GitHub/Actions", "WorkflowSuccess", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Production Deploy", { label = "cp-infra / Production Deploy" }],
            ["GitHub/Actions", "WorkflowSuccess", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Staging PR Checks", { label = "cp-infra / Staging PR Checks" }],
            ["GitHub/Actions", "WorkflowSuccess", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Production PR Checks", { label = "cp-infra / Production PR Checks" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 24
        height = 6
        properties = {
          title  = "GitHub Actions — Duration (seconds)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            ["GitHub/Actions", "WorkflowDuration", "Repository", "${var.github_owner}/cp-api", "Workflow", "CI", { label = "cp-api / CI" }],
            ["GitHub/Actions", "WorkflowDuration", "Repository", "${var.github_owner}/cp-api", "Workflow", "Release", { label = "cp-api / Release" }],
            ["GitHub/Actions", "WorkflowDuration", "Repository", "${var.github_owner}/cp-worker", "Workflow", "CI", { label = "cp-worker / CI" }],
            ["GitHub/Actions", "WorkflowDuration", "Repository", "${var.github_owner}/cp-worker", "Workflow", "Release", { label = "cp-worker / Release" }],
            ["GitHub/Actions", "WorkflowDuration", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Staging Deploy", { label = "cp-infra / Staging Deploy" }],
            ["GitHub/Actions", "WorkflowDuration", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Production Deploy", { label = "cp-infra / Production Deploy" }],
            ["GitHub/Actions", "WorkflowDuration", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Staging PR Checks", { label = "cp-infra / Staging PR Checks" }],
            ["GitHub/Actions", "WorkflowDuration", "Repository", "${var.github_owner}/cp-infra", "Workflow", "Production PR Checks", { label = "cp-infra / Production PR Checks" }]
          ]
        }
      }
    ]
  })
}

# ==========================================
# ECR Enhanced Scanning (Amazon Inspector) — optional
# Enables deep vulnerability scanning on all ECR images in the account.
# Requires Inspector to be enabled. Cost: per-image scan fee.
# Toggle with: enable_ecr_enhanced_scanning = true
# ==========================================
resource "aws_ecr_registry_scanning_configuration" "enhanced" {
  count     = var.enable_ecr_enhanced_scanning ? 1 : 0
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "SCAN_ON_PUSH"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}

# ==========================================
# App Pipeline — CI/CD for the application repo
# Triggered directly by EventBridge (no CodePipeline overhead).
#
# Three pipelines:
#   1. Branch CI  — any non-main branch: lint + basic tests + Bandit + build + push
#   2. Main CI    — main branch: full tests + Bandit + build + push + optional dev update
#   3. Tag/Promote — semver tag: promote existing image or build, then update production.tfvars
#
# Enable with: enable_app_pipeline = true
# ==========================================
locals {
  app_repo_arn   = "arn:aws:codecommit:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.app_codecommit_repo_name}"
  app_source_url = "https://git-codecommit.${var.aws_region}.amazonaws.com/v1/repos/${var.app_codecommit_repo_name}"
}

# EventBridge role to directly start CodeBuild projects (app pipelines bypass CodePipeline)
resource "aws_iam_role" "eventbridge_codebuild" {
  count = var.enable_app_pipeline ? 1 : 0
  name  = "${local.project_prefix}-eventbridge-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "eventbridge_codebuild" {
  count = var.enable_app_pipeline ? 1 : 0
  name  = "start-codebuild"
  role  = aws_iam_role.eventbridge_codebuild[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "codebuild:StartBuild"
      Resource = [
        module.codebuild_app_branch[0].project_arn,
        module.codebuild_app_main[0].project_arn,
        module.codebuild_app_tag[0].project_arn,
      ]
    }]
  })
}

# CodeBuild — Branch CI
module "codebuild_app_branch" {
  count  = var.enable_app_pipeline ? 1 : 0
  source = "../../modules/codebuild"

  project_name     = "${local.project_prefix}-app-branch"
  description      = "App branch CI: lint, basic tests, Bandit, build + push image"
  service_role_arn = var.codebuild_role_arn
  buildspec_path   = "buildspec/branch.yml"
  source_type      = "CODECOMMIT"
  source_location  = local.app_source_url
  privileged_mode  = true

  environment_variables = {
    AWS_REGION      = var.aws_region
    ECR_API_REPO    = local.ecr_api_repo_name
    ECR_WORKER_REPO = local.ecr_worker_repo_name
    ENVIRONMENT     = var.environment
  }

  tags = var.tags
}

# CodeBuild — Main CI
module "codebuild_app_main" {
  count  = var.enable_app_pipeline ? 1 : 0
  source = "../../modules/codebuild"

  project_name     = "${local.project_prefix}-app-main"
  description      = "App main CI: full tests, Bandit, build + push image, optional dev.tfvars update"
  service_role_arn = var.codebuild_role_arn
  buildspec_path   = "buildspec/main.yml"
  source_type      = "CODECOMMIT"
  source_location  = local.app_source_url
  privileged_mode  = true

  environment_variables = {
    AWS_REGION        = var.aws_region
    ECR_API_REPO      = local.ecr_api_repo_name
    ECR_WORKER_REPO   = local.ecr_worker_repo_name
    ENVIRONMENT       = var.environment
    ENABLE_DEV_UPDATE = tostring(var.enable_dev_auto_update)
    INFRA_REPO_NAME   = var.infra_repo_name
    INFRA_REPO_REGION = var.aws_region
  }

  tags = var.tags
}

# CodeBuild — Tag/Promote
module "codebuild_app_tag" {
  count  = var.enable_app_pipeline ? 1 : 0
  source = "../../modules/codebuild"

  project_name     = "${local.project_prefix}-app-tag"
  description      = "App release: promote image by retagging, commit image_tag to infra production.tfvars"
  service_role_arn = var.codebuild_role_arn
  buildspec_path   = "buildspec/tag-promote.yml"
  source_type      = "CODECOMMIT"
  source_location  = local.app_source_url
  privileged_mode  = true

  environment_variables = {
    AWS_REGION        = var.aws_region
    ECR_API_REPO      = local.ecr_api_repo_name
    ECR_WORKER_REPO   = local.ecr_worker_repo_name
    INFRA_REPO_NAME   = var.infra_repo_name
    INFRA_REPO_REGION = var.aws_region
  }

  tags = var.tags
}

# EventBridge — Branch trigger (any branch except main)
resource "aws_cloudwatch_event_rule" "app_branch" {
  count       = var.enable_app_pipeline ? 1 : 0
  name        = "${local.project_prefix}-app-branch-ci"
  description = "Trigger app branch CI on any non-main branch push"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    resources   = [local.app_repo_arn]
    detail = {
      event         = ["referenceCreated", "referenceUpdated"]
      referenceType = ["branch"]
      referenceName = [{ "anything-but" = "main" }]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "app_branch" {
  count    = var.enable_app_pipeline ? 1 : 0
  rule     = aws_cloudwatch_event_rule.app_branch[0].name
  arn      = module.codebuild_app_branch[0].project_arn
  role_arn = aws_iam_role.eventbridge_codebuild[0].arn

  input_transformer {
    input_paths = {
      branch   = "$.detail.referenceName"
      commitId = "$.detail.commitId"
    }
    input_template = <<-TEMPLATE
      {
        "sourceVersion": <branch>,
        "environmentVariablesOverride": [
          {"name": "GIT_BRANCH", "value": <branch>, "type": "PLAINTEXT"},
          {"name": "COMMIT_SHA", "value": <commitId>, "type": "PLAINTEXT"}
        ]
      }
    TEMPLATE
  }
}

# EventBridge — Main trigger
resource "aws_cloudwatch_event_rule" "app_main" {
  count       = var.enable_app_pipeline ? 1 : 0
  name        = "${local.project_prefix}-app-main-ci"
  description = "Trigger app main CI on push to main"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    resources   = [local.app_repo_arn]
    detail = {
      event         = ["referenceCreated", "referenceUpdated"]
      referenceType = ["branch"]
      referenceName = ["main"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "app_main" {
  count    = var.enable_app_pipeline ? 1 : 0
  rule     = aws_cloudwatch_event_rule.app_main[0].name
  arn      = module.codebuild_app_main[0].project_arn
  role_arn = aws_iam_role.eventbridge_codebuild[0].arn

  input_transformer {
    input_paths = {
      commitId = "$.detail.commitId"
    }
    input_template = <<-TEMPLATE
      {
        "sourceVersion": <commitId>,
        "environmentVariablesOverride": [
          {"name": "COMMIT_SHA", "value": <commitId>, "type": "PLAINTEXT"}
        ]
      }
    TEMPLATE
  }
}

# EventBridge — Tag trigger (semver tags only: v*.*.*)
resource "aws_cloudwatch_event_rule" "app_tag" {
  count       = var.enable_app_pipeline ? 1 : 0
  name        = "${local.project_prefix}-app-tag-release"
  description = "Trigger app promote/release on semver tag push (v*.*.*)"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    resources   = [local.app_repo_arn]
    detail = {
      event         = ["referenceCreated"]
      referenceType = ["tag"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "app_tag" {
  count    = var.enable_app_pipeline ? 1 : 0
  rule     = aws_cloudwatch_event_rule.app_tag[0].name
  arn      = module.codebuild_app_tag[0].project_arn
  role_arn = aws_iam_role.eventbridge_codebuild[0].arn

  input_transformer {
    input_paths = {
      tag      = "$.detail.referenceName"
      commitId = "$.detail.commitId"
    }
    input_template = <<-TEMPLATE
      {
        "sourceVersion": <tag>,
        "environmentVariablesOverride": [
          {"name": "IMAGE_TAG", "value": <tag>, "type": "PLAINTEXT"},
          {"name": "COMMIT_SHA", "value": <commitId>, "type": "PLAINTEXT"}
        ]
      }
    TEMPLATE
  }
}

# ==========================================
# Data Sources
# ==========================================
data "aws_caller_identity" "current" {}

# Look up ECR repos created by the bootstrap layer (used when create_ecr_repositories = false)
data "aws_ecr_repository" "api" {
  count = var.create_ecr_repositories ? 0 : 1
  name  = "${var.project_name}-api"
}

data "aws_ecr_repository" "worker" {
  count = var.create_ecr_repositories ? 0 : 1
  name  = "${var.project_name}-worker"
}

# ==========================================
# CI/CD — CodeBuild Projects
# ==========================================
module "codebuild_api" {
  count  = var.enable_cicd ? 1 : 0
  source = "../../modules/codebuild"

  project_name     = "${local.project_prefix}-build-api"
  description      = "Build and push API Docker image to ECR"
  service_role_arn = var.codebuild_role_arn
  buildspec_path   = "buildspec/build-api.yml"
  privileged_mode  = true

  environment_variables = {
    AWS_REGION     = var.aws_region
    ECR_API_REPO   = local.ecr_api_repo_name
    ENVIRONMENT    = var.environment
    ENABLE_METRICS = tostring(var.enable_pipeline_metrics)
  }

  tags = var.tags
}

module "codebuild_worker" {
  count  = var.enable_cicd ? 1 : 0
  source = "../../modules/codebuild"

  project_name     = "${local.project_prefix}-build-worker"
  description      = "Build and push Worker Docker image to ECR"
  service_role_arn = var.codebuild_role_arn
  buildspec_path   = "buildspec/build-worker.yml"
  privileged_mode  = true

  environment_variables = {
    AWS_REGION      = var.aws_region
    ECR_WORKER_REPO = local.ecr_worker_repo_name
    ENVIRONMENT     = var.environment
    ENABLE_METRICS  = tostring(var.enable_pipeline_metrics)
  }

  tags = var.tags
}

module "codebuild_tf_plan" {
  count  = var.enable_cicd ? 1 : 0
  source = "../../modules/codebuild"

  project_name     = "${local.project_prefix}-tf-plan"
  description      = "Run Terraform fmt, validate, and plan"
  service_role_arn = var.codebuild_role_arn
  buildspec_path   = "buildspec/terraform-plan.yml"
  privileged_mode  = false

  environment_variables = {
    AWS_REGION        = var.aws_region
    TF_BACKEND_BUCKET = var.tf_backend_bucket
    TF_BACKEND_KEY    = "envs/eus2/terraform.tfstate"
    TF_BACKEND_REGION = var.aws_region
    TF_LOCK_TABLE     = var.tf_lock_table
    TF_ENVIRONMENT    = var.environment
    # API token is managed by bootstrap, read via data.aws_ssm_parameter.api_token
  }

  tags = var.tags
}

module "codebuild_tf_apply" {
  count  = var.enable_cicd ? 1 : 0
  source = "../../modules/codebuild"

  project_name     = "${local.project_prefix}-tf-apply"
  description      = "Apply reviewed Terraform plan"
  service_role_arn = var.codebuild_role_arn
  buildspec_path   = "buildspec/terraform-apply.yml"
  privileged_mode  = false

  environment_variables = {
    AWS_REGION        = var.aws_region
    TF_BACKEND_BUCKET = var.tf_backend_bucket
    TF_BACKEND_KEY    = "envs/eus2/terraform.tfstate"
    TF_BACKEND_REGION = var.aws_region
    TF_LOCK_TABLE     = var.tf_lock_table
  }

  tags = var.tags
}

# ==========================================
# CI/CD — CodePipeline Pipelines
# ==========================================
module "pipeline_main" {
  count  = var.enable_cicd ? 1 : 0
  source = "../../modules/codepipeline"

  pipeline_name        = "${local.project_prefix}-main"
  pipeline_type        = "main"
  role_arn             = var.codepipeline_role_arn
  artifact_bucket      = var.artifact_bucket_name
  codecommit_repo_name = var.codecommit_repo_name
  branch               = "main"
  eventbridge_role_arn = var.eventbridge_role_arn

  codebuild_api_project      = module.codebuild_api[0].project_name
  codebuild_worker_project   = module.codebuild_worker[0].project_name
  codebuild_tf_plan_project  = module.codebuild_tf_plan[0].project_name
  codebuild_tf_apply_project = module.codebuild_tf_apply[0].project_name

  tags = var.tags
}

module "pipeline_release" {
  count  = var.enable_cicd ? 1 : 0
  source = "../../modules/codepipeline"

  pipeline_name        = "${local.project_prefix}-release"
  pipeline_type        = "release"
  role_arn             = var.codepipeline_role_arn
  artifact_bucket      = var.artifact_bucket_name
  codecommit_repo_name = var.codecommit_repo_name
  branch               = "main"
  eventbridge_role_arn = var.eventbridge_role_arn

  codebuild_api_project      = module.codebuild_api[0].project_name
  codebuild_worker_project   = module.codebuild_worker[0].project_name
  codebuild_tf_plan_project  = module.codebuild_tf_plan[0].project_name
  codebuild_tf_apply_project = module.codebuild_tf_apply[0].project_name

  tags = var.tags
}

# ==========================================
# SSM Parameter Store — Infrastructure Outputs
# ==========================================
resource "aws_ssm_parameter" "infra_output" {
  for_each = {
    alb_url             = "https://${module.alb.load_balancer_dns_name}"
    sqs_queue_url       = module.sqs_messages.queue_url
    s3_bucket_name      = module.s3_messages.bucket_name
    ecs_cluster_name    = module.ecs_cluster.cluster_name
    api_service_name    = module.ecs_service_api.service_name
    worker_service_name = module.ecs_service_worker.service_name
  }

  name      = "/${var.project_name}/${var.environment}/outputs/${each.key}"
  type      = "String"
  value     = each.value
  overwrite = true

  tags = merge(var.tags, {
    Name = "/${var.project_name}/${var.environment}/outputs/${each.key}"
  })
}

resource "aws_ssm_parameter" "cloudwatch_dashboard_url" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name      = "/${var.project_name}/${var.environment}/outputs/cloudwatch_dashboard_url"
  type      = "String"
  value     = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main[0].dashboard_name}"
  overwrite = true

  tags = merge(var.tags, {
    Name = "/${var.project_name}/${var.environment}/outputs/cloudwatch_dashboard_url"
  })
}
