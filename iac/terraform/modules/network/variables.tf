# Network Module Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (test, staging, production, dev)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets (cost optimization)"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = false
}

# ==========================================
# VPC Endpoints
# ==========================================
# S3 Gateway endpoint — FREE, always recommended.
# Routes S3 traffic (ECR image layers, Worker S3 writes) directly within AWS
# without going through the NAT Gateway, reducing NAT costs and latency.
variable "enable_s3_endpoint" {
  description = "Enable S3 Gateway VPC endpoint (free — routes S3 traffic inside AWS, bypasses NAT)"
  type        = bool
  default     = true
}

# Interface endpoints — each costs ~$0.01/hour per AZ (~$7/month for 1 AZ).
# Enable when NAT Gateway costs exceed endpoint costs, or for strict private networking.
# Covers: SQS (API→queue, Worker polling), SSM (API token), ECR (image pulls), CloudWatch Logs.
variable "enable_interface_endpoints" {
  description = "Enable Interface VPC endpoints for SQS, SSM, ECR, and CloudWatch Logs (~$0.01/hr each)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
