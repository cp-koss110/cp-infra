# SQS Module Variables

variable "queue_name" {
  description = "Name of the SQS queue"
  type        = string
}

variable "delay_seconds" {
  description = "Delay in seconds for message delivery"
  type        = number
  default     = 0
}

variable "max_message_size" {
  description = "Maximum message size in bytes (1024-262144)"
  type        = number
  default     = 262144
}

variable "message_retention_seconds" {
  description = "Number of seconds to retain messages (60-1209600)"
  type        = number
  default     = 345600 # 4 days
}

variable "receive_wait_time_seconds" {
  description = "Long polling wait time in seconds (0-20)"
  type        = number
  default     = 20
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout in seconds (0-43200)"
  type        = number
  default     = 30
}

variable "kms_master_key_id" {
  description = "KMS key ID for encryption (null for SQS managed)"
  type        = string
  default     = null
}

# Dead Letter Queue Configuration
variable "create_dlq" {
  description = "Create a Dead Letter Queue"
  type        = bool
  default     = false
}

variable "max_receive_count" {
  description = "Max receive count before sending to DLQ"
  type        = number
  default     = 5
}

variable "dlq_message_retention_seconds" {
  description = "DLQ message retention in seconds"
  type        = number
  default     = 1209600 # 14 days
}

# FIFO Configuration
variable "fifo_queue" {
  description = "Create a FIFO queue"
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enable content-based deduplication for FIFO queue"
  type        = bool
  default     = false
}

variable "deduplication_scope" {
  description = "Deduplication scope (messageGroup or queue)"
  type        = string
  default     = "queue"
}

variable "fifo_throughput_limit" {
  description = "FIFO throughput limit (perQueue or perMessageGroupId)"
  type        = string
  default     = "perQueue"
}

# Queue Policies
variable "queue_policy" {
  description = "JSON queue policy (null for no policy)"
  type        = string
  default     = null
}

variable "dlq_policy" {
  description = "JSON DLQ policy (null for no policy)"
  type        = string
  default     = null
}

# CloudWatch Alarms
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for queue depth"
  type        = bool
  default     = false
}

variable "alarm_threshold" {
  description = "Queue depth threshold for alarm"
  type        = number
  default     = 1000
}

variable "alarm_period" {
  description = "Alarm evaluation period in seconds"
  type        = number
  default     = 300
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
