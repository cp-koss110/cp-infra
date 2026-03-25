# CodeBuild Module Variables

variable "project_name" {
  description = "Name of the CodeBuild project"
  type        = string
}

variable "description" {
  description = "Description of the CodeBuild project"
  type        = string
  default     = ""
}

variable "service_role_arn" {
  description = "IAM role ARN for CodeBuild to assume"
  type        = string
}

variable "buildspec_path" {
  description = "Path to the buildspec file relative to repo root (e.g. buildspec/build-api.yml)"
  type        = string
}

variable "environment_variables" {
  description = "Map of environment variables to inject into the build"
  type        = map(string)
  default     = {}
}

variable "compute_type" {
  description = "CodeBuild compute type"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "image" {
  description = "CodeBuild Docker image"
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "privileged_mode" {
  description = "Enable privileged mode (required for Docker builds)"
  type        = bool
  default     = true
}

variable "build_timeout" {
  description = "Build timeout in minutes"
  type        = number
  default     = 20
}

variable "source_type" {
  description = "CodeBuild source type: CODEPIPELINE (default, managed by pipeline) or CODECOMMIT (direct trigger)"
  type        = string
  default     = "CODEPIPELINE"
}

variable "source_location" {
  description = "CodeCommit HTTPS URL (required when source_type = CODECOMMIT)"
  type        = string
  default     = null
}

variable "git_clone_depth" {
  description = "Git clone depth for CODECOMMIT source (1 = shallow, faster)"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
