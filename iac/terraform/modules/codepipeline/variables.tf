# CodePipeline Module Variables

variable "pipeline_name" {
  description = "Name of the CodePipeline"
  type        = string
}

variable "role_arn" {
  description = "IAM role ARN for CodePipeline to assume"
  type        = string
}

variable "artifact_bucket" {
  description = "S3 bucket name for pipeline artifacts"
  type        = string
}

variable "codecommit_repo_name" {
  description = "Name of the source CodeCommit repository"
  type        = string
}

variable "branch" {
  description = "Source branch to monitor (for main pipeline)"
  type        = string
  default     = "main"
}

variable "pipeline_type" {
  description = "Pipeline type: 'main' (build+plan only) or 'release' (build+plan+apply)"
  type        = string
  default     = "main"

  validation {
    condition     = contains(["main", "release"], var.pipeline_type)
    error_message = "pipeline_type must be 'main' or 'release'"
  }
}

variable "codebuild_api_project" {
  description = "Name of the CodeBuild project for API image build"
  type        = string
}

variable "codebuild_worker_project" {
  description = "Name of the CodeBuild project for Worker image build"
  type        = string
}

variable "codebuild_tf_plan_project" {
  description = "Name of the CodeBuild project for Terraform plan"
  type        = string
}

variable "codebuild_tf_apply_project" {
  description = "Name of the CodeBuild project for Terraform apply (used in release pipeline)"
  type        = string
}

variable "eventbridge_role_arn" {
  description = "IAM role ARN for EventBridge to trigger the release pipeline (required for pipeline_type = release)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
