# CodeBuild Module
# Creates a CodeBuild project intended for use within a CodePipeline.

resource "aws_codebuild_project" "this" {
  name          = var.project_name
  description   = var.description
  service_role  = var.service_role_arn
  build_timeout = var.build_timeout

  artifacts {
    type = var.source_type == "CODEPIPELINE" ? "CODEPIPELINE" : "NO_ARTIFACTS"
  }

  environment {
    compute_type                = var.compute_type
    image                       = var.image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = var.privileged_mode

    dynamic "environment_variable" {
      for_each = var.environment_variables
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  source {
    type            = var.source_type
    buildspec       = var.buildspec_path
    location        = var.source_type == "CODECOMMIT" ? var.source_location : null
    git_clone_depth = var.source_type == "CODECOMMIT" ? var.git_clone_depth : null
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/codebuild/${var.project_name}"
      stream_name = "build"
      status      = "ENABLED"
    }
  }

  tags = merge(var.tags, {
    Name = var.project_name
  })
}
