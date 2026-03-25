# SSM Parameter Module Variables

variable "parameter_name" {
  description = "Name of the SSM parameter (must start with /)"
  type        = string

  validation {
    condition     = can(regex("^/", var.parameter_name))
    error_message = "parameter_name must start with /"
  }
}

variable "parameter_value" {
  description = "Value of the SSM parameter"
  type        = string
  sensitive   = true
}

variable "parameter_type" {
  description = "Type of parameter (String, StringList, or SecureString)"
  type        = string
  default     = "SecureString"

  validation {
    condition     = contains(["String", "StringList", "SecureString"], var.parameter_type)
    error_message = "parameter_type must be String, StringList, or SecureString"
  }
}

variable "description" {
  description = "Description of the parameter"
  type        = string
  default     = ""
}

variable "tier" {
  description = "Parameter tier (Standard or Advanced)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Advanced"], var.tier)
    error_message = "tier must be Standard or Advanced"
  }
}

variable "kms_key_id" {
  description = "KMS key ID for SecureString encryption (null for default)"
  type        = string
  default     = null
}

variable "data_type" {
  description = "Data type of the parameter (text, aws:ec2:image, etc.)"
  type        = string
  default     = "text"
}

variable "overwrite" {
  description = "Overwrite existing parameter"
  type        = bool
  default     = true
}

variable "allowed_pattern" {
  description = "Regex pattern for parameter validation"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to the parameter"
  type        = map(string)
  default     = {}
}
