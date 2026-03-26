# Bootstrap Layer Variables

variable "aws_region" {
  description = "AWS region to deploy bootstrap resources into"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Project name used as a prefix for all resource names and as the Project tag value"
  type        = string
  default     = "exam-costa"
}

variable "owner" {
  description = "Owner tag applied to all resources — identifies who is responsible"
  type        = string
  default     = "Costa"
}

variable "force_destroy" {
  description = "Allow S3 buckets and ECR repositories to be destroyed even if non-empty. Enable for dev/exam cleanup."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags merged into every resource. Use to add environment-specific or cost-tracking labels."
  type        = map(string)
  default     = {}
}
