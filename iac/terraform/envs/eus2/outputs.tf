# Environment Outputs for US-East-2 (eus2)

# ==========================================
# Network Outputs
# ==========================================
output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.network.private_subnet_ids
}

# ==========================================
# ECR Outputs
# ==========================================
output "api_ecr_repository_url" {
  description = "API ECR repository URL"
  value       = var.create_ecr_repositories ? module.ecr_api[0].repository_url : "N/A"
}

output "worker_ecr_repository_url" {
  description = "Worker ECR repository URL"
  value       = var.create_ecr_repositories ? module.ecr_worker[0].repository_url : "N/A"
}

# ==========================================
# S3 Outputs
# ==========================================
output "s3_messages_bucket_name" {
  description = "S3 bucket name for messages"
  value       = module.s3_messages.bucket_name
}

output "s3_messages_bucket_arn" {
  description = "S3 bucket ARN for messages"
  value       = module.s3_messages.bucket_arn
}

# ==========================================
# SQS Outputs
# ==========================================
output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = module.sqs_messages.queue_url
}

output "sqs_queue_arn" {
  description = "SQS queue ARN"
  value       = module.sqs_messages.queue_arn
}

output "sqs_dlq_url" {
  description = "SQS DLQ URL"
  value       = module.sqs_messages.dlq_url
}

# ==========================================
# SSM Outputs
# ==========================================
output "api_token_parameter_name" {
  description = "SSM parameter name for API token"
  value       = module.ssm_api_token.parameter_name
}

output "api_token_parameter_arn" {
  description = "SSM parameter ARN for API token"
  value       = module.ssm_api_token.parameter_arn
}

# ==========================================
# ALB Outputs
# ==========================================
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.load_balancer_dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = module.alb.load_balancer_arn
}

output "alb_zone_id" {
  description = "ALB hosted zone ID"
  value       = module.alb.load_balancer_zone_id
}

output "target_group_arn" {
  description = "Target group ARN"
  value       = module.alb.target_group_arn
}

# ==========================================
# ECS Outputs
# ==========================================
output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs_cluster.cluster_arn
}

output "api_service_name" {
  description = "API service name"
  value       = module.ecs_service_api.service_name
}

output "worker_service_name" {
  description = "Worker service name"
  value       = module.ecs_service_worker.service_name
}

output "api_task_definition_arn" {
  description = "API task definition ARN"
  value       = module.ecs_service_api.task_definition_arn
}

output "worker_task_definition_arn" {
  description = "Worker task definition ARN"
  value       = module.ecs_service_worker.task_definition_arn
}

# ==========================================
# IAM Outputs
# ==========================================
output "ecs_execution_role_arn" {
  description = "ECS execution role ARN"
  value       = module.iam_ecs_execution_role.role_arn
}

output "api_task_role_arn" {
  description = "API task role ARN"
  value       = module.iam_api_task_role.role_arn
}

output "worker_task_role_arn" {
  description = "Worker task role ARN"
  value       = module.iam_worker_task_role.role_arn
}

# ==========================================
# Quick Access Information
# ==========================================
output "quick_access" {
  description = "Quick access information"
  value = {
    api_endpoint             = "http://${module.alb.load_balancer_dns_name}"
    health_endpoint          = "http://${module.alb.load_balancer_dns_name}/healthz"
    sqs_queue_url            = module.sqs_messages.queue_url
    s3_bucket                = module.s3_messages.bucket_name
    cloudwatch_dashboard_url = var.enable_cloudwatch_monitoring ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main[0].dashboard_name}" : null
  }
}

# ==========================================
# Deployment Information
# ==========================================
output "deployment_info" {
  description = "Deployment information"
  value = {
    environment  = var.environment
    region       = var.aws_region
    image_tag    = var.image_tag
    api_image    = local.api_image
    worker_image = local.worker_image
    api_tasks    = var.api_desired_count
    worker_tasks = var.worker_desired_count
  }
}
