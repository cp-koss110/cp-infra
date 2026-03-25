# IAM Module Variables

variable "role_name" {
  description = "Name of the IAM role"
  type        = string
}

variable "role_description" {
  description = "Description of the IAM role"
  type        = string
  default     = ""
}

variable "assume_role_policy" {
  description = "JSON policy document for assume role"
  type        = string
}

variable "managed_policy_arns" {
  description = "List of managed policy ARNs to attach"
  type        = list(string)
  default     = []
}

variable "inline_policies" {
  description = "Map of inline policies (name -> policy JSON)"
  type        = map(string)
  default     = {}
}

variable "custom_policies" {
  description = "Map of custom managed policies to create (name -> {policy, description})"
  type = map(object({
    policy      = string
    description = optional(string)
  }))
  default = {}
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds"
  type        = number
  default     = 3600
}

variable "force_detach_policies" {
  description = "Force detach policies when deleting role"
  type        = bool
  default     = false
}

variable "path" {
  description = "Path for the IAM role"
  type        = string
  default     = "/"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
