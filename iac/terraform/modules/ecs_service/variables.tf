# ECS Service Module Variables

variable "service_name" {
  description = "Name of the ECS service"
  type        = string
}

variable "cluster_id" {
  description = "ID of the ECS cluster"
  type        = string
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

# Task Definition
variable "container_name" {
  description = "Name of the container"
  type        = string
}

variable "container_image" {
  description = "Docker image for the container"
  type        = string
}

variable "container_port" {
  description = "Port exposed by container (0 for no port)"
  type        = number
  default     = 0
}

variable "cpu" {
  description = "CPU units for task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory for task in MB"
  type        = number
  default     = 512
}

variable "execution_role_arn" {
  description = "ARN of task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of task role"
  type        = string
}

# Environment Variables
variable "environment_variables" {
  description = "Map of environment variables"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of secrets (name -> SSM parameter ARN)"
  type        = map(string)
  default     = {}
}

# Container Configuration
variable "container_health_check" {
  description = "Container health check configuration"
  type = object({
    command     = list(string)
    interval    = optional(number)
    timeout     = optional(number)
    retries     = optional(number)
    startPeriod = optional(number)
  })
  default = null
}

variable "ulimits" {
  description = "Container ulimits"
  type = list(object({
    name      = string
    softLimit = number
    hardLimit = number
  }))
  default = []
}

variable "mount_points" {
  description = "Container mount points"
  type = list(object({
    sourceVolume  = string
    containerPath = string
    readOnly      = optional(bool)
  }))
  default = []
}

variable "volumes_from" {
  description = "Volumes to mount from other containers"
  type = list(object({
    sourceContainer = string
    readOnly        = optional(bool)
  }))
  default = []
}

variable "efs_volumes" {
  description = "EFS volumes to mount"
  type = list(object({
    name                    = string
    file_system_id          = string
    root_directory          = optional(string)
    transit_encryption      = optional(string)
    transit_encryption_port = optional(number)
    access_point_id         = optional(string)
    iam                     = optional(string)
  }))
  default = []
}

# Networking
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "security_groups" {
  description = "List of security group IDs"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign public IP to tasks"
  type        = bool
  default     = false
}

# Load Balancer
variable "target_group_arn" {
  description = "ARN of target group (null for no load balancer)"
  type        = string
  default     = null
}

variable "health_check_grace_period_seconds" {
  description = "Health check grace period for load balancer"
  type        = number
  default     = 0
}

# Service Discovery
variable "service_registry_arn" {
  description = "ARN of service registry (null for no service discovery)"
  type        = string
  default     = null
}

# Deployment
variable "launch_type" {
  description = "Launch type (FARGATE or EC2)"
  type        = string
  default     = "FARGATE"
}

variable "platform_version" {
  description = "Fargate platform version"
  type        = string
  default     = "LATEST"
}

variable "deployment_maximum_percent" {
  description = "Maximum percent of tasks during deployment"
  type        = number
  default     = 200
}

variable "deployment_minimum_healthy_percent" {
  description = "Minimum healthy percent during deployment"
  type        = number
  default     = 100
}

variable "enable_deployment_circuit_breaker" {
  description = "Enable deployment circuit breaker"
  type        = bool
  default     = true
}

variable "enable_deployment_rollback" {
  description = "Enable automatic rollback on failure"
  type        = bool
  default     = true
}

variable "force_new_deployment" {
  description = "Force new deployment on apply"
  type        = bool
  default     = false
}

# Auto Scaling
variable "enable_autoscaling" {
  description = "Enable auto scaling"
  type        = bool
  default     = false
}

variable "autoscaling_min_capacity" {
  description = "Minimum number of tasks"
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of tasks"
  type        = number
  default     = 10
}

variable "autoscaling_cpu_target" {
  description = "Target CPU utilization (0 to disable)"
  type        = number
  default     = 70
}

variable "autoscaling_memory_target" {
  description = "Target memory utilization (0 to disable)"
  type        = number
  default     = 0
}

variable "autoscaling_scale_in_cooldown" {
  description = "Scale in cooldown in seconds"
  type        = number
  default     = 300
}

variable "autoscaling_scale_out_cooldown" {
  description = "Scale out cooldown in seconds"
  type        = number
  default     = 60
}

# CloudWatch Logs
variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 7
}

variable "aws_region" {
  description = "AWS region for logs"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
