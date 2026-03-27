# ALB Module Variables

variable "name" {
  description = "Name of the load balancer"
  type        = string
}

variable "internal" {
  description = "Create internal load balancer"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for target group"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for load balancer"
  type        = list(string)
}

variable "security_groups" {
  description = "List of security group IDs"
  type        = list(string)
}

# Load Balancer Configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "enable_http2" {
  description = "Enable HTTP/2"
  type        = bool
  default     = true
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing"
  type        = bool
  default     = true
}

variable "idle_timeout" {
  description = "Idle timeout in seconds"
  type        = number
  default     = 60
}

variable "drop_invalid_header_fields" {
  description = "Drop invalid header fields"
  type        = bool
  default     = true
}

# Access Logs
variable "access_logs_bucket" {
  description = "S3 bucket for access logs (null to disable)"
  type        = string
  default     = null
}

variable "access_logs_prefix" {
  description = "S3 prefix for access logs"
  type        = string
  default     = "alb-logs"
}

# Target Group Configuration
variable "target_port" {
  description = "Port for target group"
  type        = number
}

variable "target_protocol" {
  description = "Protocol for target group (HTTP or HTTPS)"
  type        = string
  default     = "HTTP"
}

variable "target_type" {
  description = "Type of target (instance, ip, or lambda)"
  type        = string
  default     = "ip"
}

variable "deregistration_delay" {
  description = "Deregistration delay in seconds"
  type        = number
  default     = 30
}

variable "slow_start" {
  description = "Slow start duration in seconds (0 to disable)"
  type        = number
  default     = 0
}

# Health Check Configuration
variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/healthz"
}

variable "health_check_protocol" {
  description = "Health check protocol"
  type        = string
  default     = "HTTP"
}

variable "health_check_matcher" {
  description = "Health check success codes"
  type        = string
  default     = "200"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "Healthy threshold count"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Unhealthy threshold count"
  type        = number
  default     = 3
}

# Stickiness
variable "enable_stickiness" {
  description = "Enable session stickiness"
  type        = bool
  default     = false
}

variable "stickiness_type" {
  description = "Stickiness type (lb_cookie or app_cookie)"
  type        = string
  default     = "lb_cookie"
}

variable "stickiness_cookie_duration" {
  description = "Stickiness cookie duration in seconds"
  type        = number
  default     = 86400
}

# HTTPS Configuration
variable "certificate_arn" {
  description = "ARN of SSL certificate (null for HTTP only)"
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "SSL policy for HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS-1-2-2017-01"
}

variable "enable_https_redirect" {
  description = "Redirect HTTP to HTTPS"
  type        = bool
  default     = false
}

# Listener Rules
variable "listener_rules" {
  description = "Map of listener rules (name -> {priority, path_patterns, host_headers})"
  type = map(object({
    priority      = number
    path_patterns = optional(list(string))
    host_headers  = optional(list(string))
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
