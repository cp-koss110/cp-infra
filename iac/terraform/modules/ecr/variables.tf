# ECR Module Variables

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "image_tag_mutability" {
  description = "Image tag mutability (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE"
  }
}

variable "scan_on_push" {
  description = "Enable vulnerability scanning on image push"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (null for AES256)"
  type        = string
  default     = null
}

variable "lifecycle_policy" {
  description = "JSON lifecycle policy (null to use default)"
  type        = string
  default     = null
}

variable "enable_default_lifecycle" {
  description = "Enable default lifecycle policy if none provided"
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Maximum number of images to keep (for default lifecycle)"
  type        = number
  default     = 10
}

variable "repository_policy" {
  description = "JSON repository policy (null for no policy)"
  type        = string
  default     = null
}

variable "force_delete" {
  description = "Force delete the repository even if it contains images"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
