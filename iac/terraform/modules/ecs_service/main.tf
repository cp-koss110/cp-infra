# ECS Service Module - Task Definition and Service
# Creates ECS Fargate service with task definition, logging, and auto-scaling

# ==========================================
# CloudWatch Log Group
# ==========================================
resource "aws_cloudwatch_log_group" "service" {
  name              = "/ecs/${var.service_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# ==========================================
# Task Definition
# ==========================================
resource "aws_ecs_task_definition" "main" {
  family                   = var.service_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory

  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn

  container_definitions = jsonencode([{
    name      = var.container_name
    image     = var.container_image
    essential = true

    portMappings = var.container_port > 0 ? [{
      containerPort = var.container_port
      protocol      = "tcp"
    }] : []

    environment = [
      for k, v in var.environment_variables : {
        name  = k
        value = v
      }
    ]

    secrets = [
      for k, v in var.secrets : {
        name      = k
        valueFrom = v
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = var.container_health_check != null ? var.container_health_check : null

    # Resource limits
    ulimits = var.ulimits

    # Mount points
    mountPoints = var.mount_points

    # Volumes from
    volumesFrom = var.volumes_from
  }])

  # EFS volumes (optional)
  dynamic "volume" {
    for_each = var.efs_volumes

    content {
      name = volume.value.name

      efs_volume_configuration {
        file_system_id          = volume.value.file_system_id
        root_directory          = lookup(volume.value, "root_directory", "/")
        transit_encryption      = lookup(volume.value, "transit_encryption", "ENABLED")
        transit_encryption_port = lookup(volume.value, "transit_encryption_port", null)

        dynamic "authorization_config" {
          for_each = lookup(volume.value, "access_point_id", null) != null ? [1] : []

          content {
            access_point_id = volume.value.access_point_id
            iam             = lookup(volume.value, "iam", "DISABLED")
          }
        }
      }
    }
  }

  tags = var.tags
}

# ==========================================
# ECS Service
# ==========================================
resource "aws_ecs_service" "main" {
  name            = var.service_name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count

  launch_type = var.launch_type

  # Fargate platform version
  platform_version = var.platform_version

  # Deployment configuration
  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent

  # Health check grace period (for ALB)
  health_check_grace_period_seconds = var.health_check_grace_period_seconds > 0 ? var.health_check_grace_period_seconds : null

  # Network configuration
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_groups
    assign_public_ip = var.assign_public_ip
  }

  # Load balancer configuration (optional)
  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []

    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  # Service discovery (optional)
  dynamic "service_registries" {
    for_each = var.service_registry_arn != null ? [1] : []

    content {
      registry_arn = var.service_registry_arn
    }
  }

  # Deployment circuit breaker
  deployment_circuit_breaker {
    enable   = var.enable_deployment_circuit_breaker
    rollback = var.enable_deployment_rollback
  }

  # Force new deployment on changes
  force_new_deployment = var.force_new_deployment

  # Propagate tags
  propagate_tags = "TASK_DEFINITION"

  tags = var.tags

  # Ensure proper lifecycle
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_cloudwatch_log_group.service]
}

# ==========================================
# Auto Scaling Target (Optional)
# ==========================================
resource "aws_appautoscaling_target" "ecs" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${split("/", var.cluster_id)[1]}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU-based Auto Scaling
resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling && var.autoscaling_cpu_target > 0 ? 1 : 0

  name               = "${var.service_name}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
  }
}

# Memory-based Auto Scaling
resource "aws_appautoscaling_policy" "memory" {
  count = var.enable_autoscaling && var.autoscaling_memory_target > 0 ? 1 : 0

  name               = "${var.service_name}-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = var.autoscaling_memory_target
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
  }
}
