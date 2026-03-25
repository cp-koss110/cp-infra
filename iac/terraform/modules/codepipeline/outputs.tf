output "pipeline_name" {
  description = "Name of the CodePipeline"
  value       = var.pipeline_type == "main" ? aws_codepipeline.main[0].name : aws_codepipeline.release[0].name
}

output "pipeline_arn" {
  description = "ARN of the CodePipeline"
  value       = var.pipeline_type == "main" ? aws_codepipeline.main[0].arn : aws_codepipeline.release[0].arn
}
