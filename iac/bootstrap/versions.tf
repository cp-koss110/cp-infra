terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Bootstrap intentionally uses LOCAL state.
  # The terraform.tfstate file it produces must be kept safe — it tracks
  # the S3 bucket, DynamoDB table, CodeCommit repo, and ECR repos that
  # everything else depends on.
  # Do NOT add iac/bootstrap/terraform.tfstate to .gitignore in production.
}
