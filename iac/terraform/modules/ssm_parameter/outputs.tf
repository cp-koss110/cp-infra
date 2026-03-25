# SSM Parameter Module Outputs

output "parameter_name" {
  description = "Name of the SSM parameter"
  value       = aws_ssm_parameter.this.name
}

output "parameter_arn" {
  description = "ARN of the SSM parameter"
  value       = aws_ssm_parameter.this.arn
}

output "parameter_type" {
  description = "Type of the SSM parameter"
  value       = aws_ssm_parameter.this.type
}

output "parameter_version" {
  description = "Version of the SSM parameter"
  value       = aws_ssm_parameter.this.version
}
