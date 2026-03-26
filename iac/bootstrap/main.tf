# Bootstrap Layer
# ============================================================
# Creates the foundational AWS resources that must exist before
# the main Terraform layer (iac/terraform/envs/eus2) can run.
#
# What this creates:
#   - S3 bucket        — remote Terraform state storage
#   - DynamoDB table   — Terraform state locking
#   - ECR repo (api)   — Docker images for the API service
#   - ECR repo (worker)— Docker images for the Worker service
#   - SSM parameters   — bootstrap outputs discoverable at runtime
#
# What is NOT managed here:
#   - The API auth token (/exam-costa/api/token) is written by
#     `make bootstrap` so the secret never enters Terraform state.
#
# This layer uses LOCAL state (terraform.tfstate lives here).
# Keep that file in version control — losing it means losing track
# of these shared foundational resources.
#
# Run via Makefile (recommended — also creates the API token):
#   make bootstrap
#
# Or manually:
#   terraform init
#   terraform plan -out=bootstrap.tfplan
#   terraform apply bootstrap.tfplan
# ============================================================

# ==========================================
# S3 — Terraform Remote State Bucket
#
# Name is hardcoded as TF_BACKEND_BUCKET in all three GitHub Actions
# deploy workflows and in backend.hcl.example.
# Do not rename without updating those files.
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
#
# Name is hardcoded as TF_LOCK_TABLE in all three GitHub Actions
# deploy workflows and in backend.hcl.example.
# Do not rename without updating those files.
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
# ECR Repositories
#
# Created here — before the main layer — so GitHub Actions can push
# Docker images on the first tag push without waiting for a full apply.
#
# Repository names MUST match the ECR_REPO env var in:
#   cp-api/.github/workflows/release.yml    → exam-costa-api
#   cp-worker/.github/workflows/release.yml → exam-costa-worker
#
# The main layer reads these via data sources when
# create_ecr_repositories = false (set in staging/prod tfvars).
# ==========================================
module "ecr_api" {
  source = "../terraform/modules/ecr"

  repository_name          = "${var.project_name}-api"
  image_tag_mutability     = "MUTABLE"
  scan_on_push             = true
  enable_default_lifecycle = true
  max_image_count          = 50
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
# SSM Parameter Store — Bootstrap Outputs
#
# Writes key resource identifiers to SSM so that pipelines and team
# members can discover them without direct access to terraform.tfstate.
#
# Parameters live under /${var.project_name}/bootstrap/
#
# The API auth token (/exam-costa/api/token) is intentionally absent —
# it is written by `make bootstrap` so the value never appears in state.
# ==========================================
locals {
  ssm_outputs = {
    ecr_api_url         = module.ecr_api.repository_url
    ecr_worker_url      = module.ecr_worker.repository_url
    backend_bucket_name = aws_s3_bucket.tf_state.bucket
    lock_table_name     = aws_dynamodb_table.tf_locks.name
  }
}

resource "aws_ssm_parameter" "bootstrap_outputs" {
  for_each = local.ssm_outputs

  name  = "/${var.project_name}/bootstrap/${each.key}"
  type  = "String"
  value = each.value

  tags = {
    Purpose = "bootstrap-output"
  }
}
