# SQS Module - Queue with Dead Letter Queue (DLQ)
# Creates SQS queue with optional DLQ and configurable settings

# ==========================================
# Main SQS Queue
# ==========================================
resource "aws_sqs_queue" "main" {
  name                       = var.queue_name
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  # DLQ Configuration
  redrive_policy = var.create_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null

  # Server-side encryption
  sqs_managed_sse_enabled = var.kms_master_key_id == null ? true : null
  kms_master_key_id       = var.kms_master_key_id

  # FIFO configuration
  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.fifo_queue ? var.content_based_deduplication : null
  deduplication_scope         = var.fifo_queue ? var.deduplication_scope : null
  fifo_throughput_limit       = var.fifo_queue ? var.fifo_throughput_limit : null

  tags = merge(var.tags, {
    Name = var.queue_name
  })
}

# ==========================================
# Dead Letter Queue (DLQ)
# ==========================================
resource "aws_sqs_queue" "dlq" {
  count = var.create_dlq ? 1 : 0

  name                       = "${var.queue_name}-dlq"
  message_retention_seconds  = var.dlq_message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  # Server-side encryption
  sqs_managed_sse_enabled = var.kms_master_key_id == null ? true : null
  kms_master_key_id       = var.kms_master_key_id

  # FIFO configuration for DLQ
  fifo_queue = var.fifo_queue

  tags = merge(var.tags, {
    Name = "${var.queue_name}-dlq"
    Type = "DLQ"
  })
}

# ==========================================
# Queue Policy (Optional)
# ==========================================
resource "aws_sqs_queue_policy" "main" {
  count = var.queue_policy != null ? 1 : 0

  queue_url = aws_sqs_queue.main.id
  policy    = var.queue_policy
}

resource "aws_sqs_queue_policy" "dlq" {
  count = var.create_dlq && var.dlq_policy != null ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].id
  policy    = var.dlq_policy
}

# ==========================================
# CloudWatch Alarms for Queue Depth (Optional)
# ==========================================
resource "aws_cloudwatch_metric_alarm" "queue_depth" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.queue_name}-depth-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.alarm_threshold
  alarm_description   = "Alert when ${var.queue_name} has too many messages"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.main.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  count = var.create_dlq && var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.queue_name}-dlq-depth-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Alert when ${var.queue_name} DLQ receives messages"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq[0].name
  }

  tags = var.tags
}
