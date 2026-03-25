output "aws_region" {
  description = "AWS region used by the bootstrap layer"
  value       = var.aws_region
}

output "backend_bucket_name" {
  description = "S3 bucket name for Terraform remote state"
  value       = aws_s3_bucket.tf_state.bucket
}

output "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  value       = aws_dynamodb_table.tf_locks.name
}

output "artifact_bucket_name" {
  description = "S3 bucket name for CodePipeline artifacts"
  value       = aws_s3_bucket.pipeline_artifacts.bucket
}

output "codecommit_clone_url_http" {
  description = "HTTPS clone URL for the infra CodeCommit repository"
  value       = aws_codecommit_repository.this.clone_url_http
}

output "codecommit_clone_url_grc" {
  description = "GRC clone URL for the infra CodeCommit repository"
  value       = "codecommit::${var.aws_region}://${var.codecommit_repo_name}"
}

output "app_codecommit_clone_url_http" {
  description = "HTTPS clone URL for the app CodeCommit repository"
  value       = aws_codecommit_repository.app.clone_url_http
}

output "app_codecommit_clone_url_grc" {
  description = "GRC clone URL for the app CodeCommit repository"
  value       = "codecommit::${var.aws_region}://${var.app_codecommit_repo_name}"
}

output "ecr_api_url" {
  description = "ECR repository URL for the API service"
  value       = module.ecr_api.repository_url
}

output "ecr_worker_url" {
  description = "ECR repository URL for the Worker service"
  value       = module.ecr_worker.repository_url
}

output "codebuild_role_arn" {
  description = "IAM role ARN for CodeBuild"
  value       = module.iam_codebuild.role_arn
}

output "codepipeline_role_arn" {
  description = "IAM role ARN for CodePipeline"
  value       = module.iam_codepipeline.role_arn
}

output "eventbridge_role_arn" {
  description = "IAM role ARN for EventBridge (tag-triggered release pipeline)"
  value       = aws_iam_role.eventbridge_pipeline.arn
}
