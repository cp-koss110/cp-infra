# ECR Module - Container Registry with Lifecycle Policy
# Creates ECR repository for Docker images with security scanning and lifecycle

# ==========================================
# ECR Repository
# ==========================================
resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.kms_key_id != null ? "KMS" : "AES256"
    kms_key         = var.kms_key_id
  }

  tags = merge(var.tags, {
    Name = var.repository_name
  })
}

# ==========================================
# Lifecycle Policy
# ==========================================
resource "aws_ecr_lifecycle_policy" "this" {
  count = var.lifecycle_policy != null ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = var.lifecycle_policy
}

# ==========================================
# Repository Policy (Optional)
# ==========================================
resource "aws_ecr_repository_policy" "this" {
  count = var.repository_policy != null ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = var.repository_policy
}

# ==========================================
# Default Lifecycle Policy (if not provided)
# ==========================================
locals {
  default_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.max_image_count} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.max_image_count
      }
      action = {
        type = "expire"
      }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "default" {
  count = var.lifecycle_policy == null && var.enable_default_lifecycle ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = local.default_lifecycle_policy
}
