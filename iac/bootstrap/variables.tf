# Bootstrap Layer Variables

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
  default     = "exam-costa"
}

variable "codecommit_repo_name" {
  description = "Name of the infra CodeCommit repository"
  type        = string
  default     = "exam-costa-infra"
}

variable "app_codecommit_repo_name" {
  description = "Name of the application CodeCommit repository"
  type        = string
  default     = "exam-costa-app"
}

# When enabled, all bootstrap outputs are written to SSM Parameter Store under
# /${var.project_name}/bootstrap/. This lets other pipelines and team members
# discover values (ECR URLs, role ARNs, etc.) without reading Terraform state.
variable "store_outputs_in_ssm" {
  description = "Write bootstrap outputs to SSM Parameter Store (disabled by default)"
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow S3 buckets and ECR repositories to be destroyed even if non-empty (enable for dev)"
  type        = bool
  default     = true
}
