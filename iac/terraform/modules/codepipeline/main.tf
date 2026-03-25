# CodePipeline Module
#
# Creates either:
#   - main pipeline:    Source → Build (api+worker parallel) → Plan
#   - release pipeline: Source → Build (api+worker parallel) → Plan → Deploy
#
# The release pipeline is triggered by git tags matching ^v[0-9]+\.[0-9]+\.[0-9]+$
# via an EventBridge rule (CodePipeline has no native tag trigger).

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  region     = data.aws_region.current.name
  account_id = data.aws_caller_identity.current.account_id
  repo_arn   = "arn:aws:codecommit:${local.region}:${local.account_id}:${var.codecommit_repo_name}"
}

# ==========================================
# Main Pipeline — push to default branch
# Stages: Source → Build → Plan
# ==========================================
resource "aws_codepipeline" "main" {
  count    = var.pipeline_type == "main" ? 1 : 0
  name     = var.pipeline_name
  role_arn = var.role_arn

  artifact_store {
    location = var.artifact_bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        RepositoryName       = var.codecommit_repo_name
        BranchName           = var.branch
        PollForSourceChanges = "false" # EventBridge handles trigger
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAPI"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      run_order        = 1
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["ApiImageOutput"]
      configuration = {
        ProjectName = var.codebuild_api_project
      }
    }
    action {
      name             = "BuildWorker"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      run_order        = 1
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["WorkerImageOutput"]
      configuration = {
        ProjectName = var.codebuild_worker_project
      }
    }
  }

  stage {
    name = "Plan"
    action {
      name             = "TerraformPlan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["TfPlanOutput"]
      configuration = {
        ProjectName = var.codebuild_tf_plan_project
      }
    }
  }

  tags = merge(var.tags, {
    Name = var.pipeline_name
  })
}

# EventBridge rule to trigger main pipeline on branch push
resource "aws_cloudwatch_event_rule" "main_branch" {
  count       = var.pipeline_type == "main" ? 1 : 0
  name        = "${var.pipeline_name}-trigger"
  description = "Trigger ${var.pipeline_name} on push to ${var.branch}"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    resources   = [local.repo_arn]
    detail = {
      event         = ["referenceCreated", "referenceUpdated"]
      referenceType = ["branch"]
      referenceName = [var.branch]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "main_branch" {
  count    = var.pipeline_type == "main" ? 1 : 0
  rule     = aws_cloudwatch_event_rule.main_branch[0].name
  arn      = aws_codepipeline.main[0].arn
  role_arn = var.eventbridge_role_arn
}

# ==========================================
# Release Pipeline — semver tag push
# Stages: Source → Build → Plan → Deploy
# ==========================================
resource "aws_codepipeline" "release" {
  count    = var.pipeline_type == "release" ? 1 : 0
  name     = var.pipeline_name
  role_arn = var.role_arn

  artifact_store {
    location = var.artifact_bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        RepositoryName       = var.codecommit_repo_name
        BranchName           = var.branch
        PollForSourceChanges = "false"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAPI"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      run_order        = 1
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["ApiImageOutput"]
      configuration = {
        ProjectName = var.codebuild_api_project
      }
    }
    action {
      name             = "BuildWorker"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      run_order        = 1
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["WorkerImageOutput"]
      configuration = {
        ProjectName = var.codebuild_worker_project
      }
    }
  }

  stage {
    name = "Plan"
    action {
      name             = "TerraformPlan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["TfPlanOutput"]
      configuration = {
        ProjectName = var.codebuild_tf_plan_project
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput", "TfPlanOutput"]
      configuration = {
        ProjectName   = var.codebuild_tf_apply_project
        PrimarySource = "SourceOutput"
      }
    }
  }

  tags = merge(var.tags, {
    Name = var.pipeline_name
  })
}

# EventBridge rule to trigger release pipeline on semver tag push
resource "aws_cloudwatch_event_rule" "release_tag" {
  count       = var.pipeline_type == "release" ? 1 : 0
  name        = "${var.pipeline_name}-tag-trigger"
  description = "Trigger ${var.pipeline_name} when a semver tag is pushed"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    resources   = [local.repo_arn]
    detail = {
      event         = ["referenceCreated"]
      referenceType = ["tag"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "release_tag" {
  count    = var.pipeline_type == "release" ? 1 : 0
  rule     = aws_cloudwatch_event_rule.release_tag[0].name
  arn      = aws_codepipeline.release[0].arn
  role_arn = var.eventbridge_role_arn
}
