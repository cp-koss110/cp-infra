output "aws_region" {
  description = "AWS region used by the bootstrap layer"
  value       = var.aws_region
}

output "backend_bucket_name" {
  description = "S3 bucket name for Terraform remote state — copy into backend.hcl"
  value       = aws_s3_bucket.tf_state.bucket
}

output "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking — copy into backend.hcl"
  value       = aws_dynamodb_table.tf_locks.name
}

output "ecr_api_url" {
  description = "ECR repository URL for the API service"
  value       = module.ecr_api.repository_url
}

output "ecr_worker_url" {
  description = "ECR repository URL for the Worker service"
  value       = module.ecr_worker.repository_url
}
