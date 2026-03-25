# Bootstrap Layer
# Creates the foundational AWS resources that everything else depends on.
# This layer uses LOCAL state — keep terraform.tfstate safe!
#
# Run order:
#   1. terraform init
#   2. terraform plan -out=bootstrap.tfplan
#   3. terraform apply bootstrap.tfplan
#   4. Note the outputs — you'll need them for the main layer

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ==========================================
# S3 — Terraform Remote State Bucket
# Name must exactly match backend.hcl.example
# ==========================================
resource "aws_s3_bucket" "tf_state" {
  bucket        = "${var.project_name}-terraform-state"
  force_destroy = var.force_destroy

  tags = {
    Name    = "${var.project_name}-terraform-state"
    Purpose = "terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ==========================================
# DynamoDB — Terraform State Lock Table
# Name must exactly match backend.hcl.example
# ==========================================
resource "aws_dynamodb_table" "tf_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "${var.project_name}-terraform-locks"
    Purpose = "terraform-state-lock"
  }
}

# ==========================================
# S3 — CodePipeline Artifact Bucket
# ==========================================
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket        = "${var.project_name}-pipeline-artifacts"
  force_destroy = var.force_destroy

  tags = {
    Name    = "${var.project_name}-pipeline-artifacts"
    Purpose = "codepipeline-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket                  = aws_s3_bucket.pipeline_artifacts.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ==========================================
# CodeCommit Repositories
# ==========================================

# Infrastructure repo — holds Terraform, pipeline definitions, scripts
resource "aws_codecommit_repository" "this" {
  repository_name = var.codecommit_repo_name
  description     = "DevOps Exam - ${var.project_name} infrastructure (Terraform + CI/CD)"

  tags = {
    Name = var.codecommit_repo_name
  }
}

# Application repo — holds API + Worker services and app buildspecs
resource "aws_codecommit_repository" "app" {
  repository_name = var.app_codecommit_repo_name
  description     = "DevOps Exam - ${var.project_name} application services (API + Worker)"

  tags = {
    Name = var.app_codecommit_repo_name
  }
}

# ==========================================
# ECR Repositories
# Created here (not in main layer) so CodeBuild can push images
# before main Terraform runs for the first time.
# The main layer reads these via data sources when create_ecr_repositories = false.
# ==========================================
module "ecr_api" {
  source = "../terraform/modules/ecr"

  repository_name = "${var.project_name}-api"
  # MUTABLE allows CI to overwrite the `latest` tag on each main branch build.
  # ECR scan_on_push (basic) or Enhanced Scanning (Inspector) compensates for security.
  image_tag_mutability     = "MUTABLE"
  scan_on_push             = true
  enable_default_lifecycle = true
  max_image_count          = 50 # keep more images for branch/main/tag builds
  force_delete             = var.force_destroy

  tags = {
    Name    = "${var.project_name}-api"
    Purpose = "api-container-images"
  }
}

module "ecr_worker" {
  source = "../terraform/modules/ecr"

  repository_name          = "${var.project_name}-worker"
  image_tag_mutability     = "MUTABLE"
  scan_on_push             = true
  enable_default_lifecycle = true
  max_image_count          = 50
  force_delete             = var.force_destroy

  tags = {
    Name    = "${var.project_name}-worker"
    Purpose = "worker-container-images"
  }
}

# ==========================================
# IAM — CodeBuild Role
# ==========================================
module "iam_codebuild" {
  source = "../terraform/modules/iam"

  role_name        = "${var.project_name}-codebuild-role"
  role_description = "Role assumed by CodeBuild projects for the ${var.project_name} pipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  inline_policies = {
    ecr_push = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages", # needed for promote: check if image exists
        ]
        Resource = "*"
      }]
    })

    codecommit_rw = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          # Read: clone repos for builds and for infra-repo commit in app pipelines
          "codecommit:GitPull",
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:GetRepository",
          # Write: app tag/main pipelines commit image_tag updates to infra repo
          "codecommit:GitPush",
          "codecommit:CreateBranch",
        ]
        Resource = [
          aws_codecommit_repository.this.arn,
          aws_codecommit_repository.app.arn,
        ]
      }]
    })

    s3_artifacts = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetBucketVersioning",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*",
          aws_s3_bucket.tf_state.arn,
          "${aws_s3_bucket.tf_state.arn}/*",
        ]
      }]
    })

    cloudwatch_logs = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
          ]
          Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/codebuild/*"
        },
        {
          Effect   = "Allow"
          Action   = ["cloudwatch:PutMetricData"]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "codebuild:CreateReportGroup",
            "codebuild:CreateReport",
            "codebuild:UpdateReport",
            "codebuild:BatchPutTestCases",
          ]
          Resource = "arn:aws:codebuild:${var.aws_region}:${local.account_id}:report-group/*"
        },
      ]
    })

    ssm_read = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ssm:GetParameter",
            "ssm:GetParameters",
            "ssm:GetParametersByPath",
          ]
          Resource = "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter/${var.project_name}/*"
        },
        {
          Effect   = "Allow"
          Action   = ["ssm:DescribeParameters"]
          Resource = "*"
        },
      ]
    })

    dynamodb_lock = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.tf_locks.arn
      }]
    })

    terraform_deploy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "IAMReadWrite"
          Effect = "Allow"
          Action = [
            "iam:PassRole",
            "iam:GetRole",
            "iam:GetRolePolicy",
            "iam:ListAttachedRolePolicies",
            "iam:ListRolePolicies",
            "iam:ListInstanceProfilesForRole",
            "iam:CreateRole",
            "iam:DeleteRole",
            "iam:AttachRolePolicy",
            "iam:DetachRolePolicy",
            "iam:PutRolePolicy",
            "iam:DeleteRolePolicy",
            "iam:TagRole",
            "iam:UntagRole",
            "iam:UpdateAssumeRolePolicy",
          ]
          Resource = "arn:aws:iam::${local.account_id}:role/${var.project_name}-*"
        },
        {
          Sid    = "ECSTaskManagement"
          Effect = "Allow"
          Action = [
            "ecs:RegisterTaskDefinition",
            "ecs:DeregisterTaskDefinition",
            "ecs:DescribeTaskDefinition",
            "ecs:UpdateService",
            "ecs:DescribeServices",
            "ecs:DescribeClusters",
            "ecs:ListTaskDefinitions",
          ]
          Resource = "*"
        },
        {
          Sid    = "GeneralTerraform"
          Effect = "Allow"
          Action = [
            "ec2:Describe*",
            "ec2:Get*",
            "ec2:List*",
            "elasticloadbalancing:Describe*",
            "sqs:Get*",
            "sqs:List*",
            "s3:Get*",
            "s3:List*",
            "s3:HeadBucket",
            "cloudwatch:Describe*",
            "cloudwatch:Get*",
            "cloudwatch:List*",
            "logs:Describe*",
            "logs:List*",
            "codebuild:BatchGetProjects",
            "codebuild:List*",
            "codebuild:Get*",
            "codepipeline:Get*",
            "codepipeline:List*",
            "events:Describe*",
            "events:List*",
            "ssm:Describe*",
            "ssm:List*",
          ]
          Resource = "*"
        },
        {
          Sid      = "STSCallerIdentity"
          Effect   = "Allow"
          Action   = "sts:GetCallerIdentity"
          Resource = "*"
        },
      ]
    })
  }

  tags = {
    Name = "${var.project_name}-codebuild-role"
  }
}

# ==========================================
# IAM — CodePipeline Role
# ==========================================
module "iam_codepipeline" {
  source = "../terraform/modules/iam"

  role_name        = "${var.project_name}-codepipeline-role"
  role_description = "Role assumed by CodePipeline for the ${var.project_name} pipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  inline_policies = {
    codecommit = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:UploadArchive",
          "codecommit:GetUploadArchiveStatus",
          "codecommit:CancelUploadArchive",
          "codecommit:GetRepository",
        ]
        Resource = aws_codecommit_repository.this.arn
      }]
    })

    codebuild = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:StopBuild",
        ]
        Resource = "*"
      }]
    })

    s3_artifacts = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetBucketVersioning",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*",
        ]
      }]
    })

    iam_passrole = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = module.iam_codebuild.role_arn
      }]
    })
  }

  tags = {
    Name = "${var.project_name}-codepipeline-role"
  }
}

# ==========================================
# IAM — EventBridge Role (for tag-triggered release pipeline)
# ==========================================
resource "aws_iam_role" "eventbridge_pipeline" {
  name        = "${var.project_name}-eventbridge-pipeline-role"
  description = "Role for EventBridge to trigger the release CodePipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-eventbridge-pipeline-role"
  }
}

resource "aws_iam_role_policy" "eventbridge_pipeline" {
  name = "start-pipeline"
  role = aws_iam_role.eventbridge_pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "codepipeline:StartPipelineExecution"
      Resource = "arn:aws:codepipeline:${var.aws_region}:${local.account_id}:${var.project_name}-*"
    }]
  })
}

# ==========================================
# SSM Parameter Store — Bootstrap Outputs (optional)
# Set store_outputs_in_ssm = true to enable.
# Useful for sharing values with other teams/pipelines without exposing TF state.
# Parameters are stored under /${var.project_name}/bootstrap/
# ==========================================
locals {
  ssm_outputs = var.store_outputs_in_ssm ? {
    "ecr_api_url"              = module.ecr_api.repository_url
    "ecr_worker_url"           = module.ecr_worker.repository_url
    "codebuild_role_arn"       = module.iam_codebuild.role_arn
    "codepipeline_role_arn"    = module.iam_codepipeline.role_arn
    "eventbridge_role_arn"     = aws_iam_role.eventbridge_pipeline.arn
    "artifact_bucket_name"     = aws_s3_bucket.pipeline_artifacts.bucket
    "backend_bucket_name"      = aws_s3_bucket.tf_state.bucket
    "lock_table_name"          = aws_dynamodb_table.tf_locks.name
    "infra_repo_clone_url_grc" = "codecommit::${var.aws_region}://${var.codecommit_repo_name}"
    "app_repo_clone_url_grc"   = "codecommit::${var.aws_region}://${var.app_codecommit_repo_name}"
  } : {}
}

resource "aws_ssm_parameter" "bootstrap_outputs" {
  for_each = local.ssm_outputs

  name  = "/${var.project_name}/bootstrap/${each.key}"
  type  = "String"
  value = each.value

  tags = {
    Purpose   = "bootstrap-output"
    ManagedBy = "terraform-bootstrap"
  }
}
