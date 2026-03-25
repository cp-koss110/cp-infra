# ECS Cluster Module
# Creates ECS cluster with Container Insights and capacity providers

# ==========================================
# ECS Cluster
# ==========================================
resource "aws_ecs_cluster" "main" {
  name = var.cluster_name

  # Container Insights for monitoring
  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.tags, {
    Name = var.cluster_name
  })
}

# ==========================================
# Cluster Capacity Providers (Fargate)
# ==========================================
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = var.capacity_providers

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy

    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight            = lookup(default_capacity_provider_strategy.value, "weight", 1)
      base              = lookup(default_capacity_provider_strategy.value, "base", 0)
    }
  }
}

# ==========================================
# CloudWatch Log Group for Cluster
# ==========================================
resource "aws_cloudwatch_log_group" "cluster" {
  count = var.create_cloudwatch_log_group ? 1 : 0

  name              = "/ecs/cluster/${var.cluster_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
