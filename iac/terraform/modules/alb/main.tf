# ALB Module - Application Load Balancer
# Creates ALB with target groups, listeners, and health checks

# ==========================================
# Application Load Balancer
# ==========================================
resource "aws_lb" "main" {
  name               = var.name
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = var.security_groups
  subnets            = var.subnet_ids

  enable_deletion_protection       = var.enable_deletion_protection
  enable_http2                     = var.enable_http2
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  idle_timeout                     = var.idle_timeout
  drop_invalid_header_fields       = var.drop_invalid_header_fields

  # Access logs
  dynamic "access_logs" {
    for_each = var.access_logs_bucket != null ? [1] : []

    content {
      bucket  = var.access_logs_bucket
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}

# ==========================================
# Target Group
# ==========================================
resource "aws_lb_target_group" "main" {
  name        = "${var.name}-tg"
  port        = var.target_port
  protocol    = var.target_protocol
  vpc_id      = var.vpc_id
  target_type = var.target_type

  deregistration_delay = var.deregistration_delay
  slow_start           = var.slow_start

  # Health Check
  health_check {
    enabled             = true
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    protocol            = var.health_check_protocol
    matcher             = var.health_check_matcher
  }

  # Stickiness
  dynamic "stickiness" {
    for_each = var.enable_stickiness ? [1] : []

    content {
      type            = var.stickiness_type
      cookie_duration = var.stickiness_cookie_duration
      enabled         = true
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-tg"
  })

  # Ensure proper lifecycle
  lifecycle {
    create_before_destroy = true
  }
}

# ==========================================
# HTTP Listener (Port 80)
# ==========================================
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Default action - forward to target group or redirect to HTTPS
  dynamic "default_action" {
    for_each = var.enable_https_redirect ? [1] : []

    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.enable_https_redirect ? [] : [1]

    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.main.arn
    }
  }

  tags = var.tags
}

# ==========================================
# HTTPS Listener (Port 443) - Optional
# ==========================================
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = var.tags
}

# ==========================================
# Additional Listener Rules (Optional)
# ==========================================
resource "aws_lb_listener_rule" "custom" {
  for_each = var.listener_rules

  listener_arn = var.certificate_arn != null ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  dynamic "condition" {
    for_each = lookup(each.value, "path_patterns", null) != null ? [1] : []

    content {
      path_pattern {
        values = each.value.path_patterns
      }
    }
  }

  dynamic "condition" {
    for_each = lookup(each.value, "host_headers", null) != null ? [1] : []

    content {
      host_header {
        values = each.value.host_headers
      }
    }
  }

  tags = var.tags
}
