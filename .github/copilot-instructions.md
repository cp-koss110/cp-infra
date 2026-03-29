# Copilot Code Review Instructions — cp-infra

## What this repo does
Terraform infrastructure, GitHub Actions CI/CD pipelines, and local development stack (docker-compose + LocalStack) for the DevOps exam.

## Stack
- Terraform 1.7, AWS provider
- ECS Fargate, ALB (HTTPS), SQS, S3, SSM Parameter Store, ECR, IAM, CloudWatch
- GitHub Actions for CI/CD (staging + production environments)
- Python 3.12 for e2e smoke tests (`iac/tests/e2e/`)

## Review priorities
- **Terraform**: all resources must use `var.project_name` for naming — no hardcoded `exam-costa` strings. Tags come from `default_tags` in the provider block.
- **Secrets**: no secrets or account IDs in `.tf` files. Sensitive values come from SSM or `terraform.tfvars` (gitignored). The API token path pattern is `/{project_name}/{env}/api/token`.
- **IAM**: least-privilege. ECS task roles should only have the permissions they need (SQS send/receive, S3 put, SSM get).
- **State**: backend config uses `backend.hcl` (not committed). State bucket and lock table names come from env vars / Makefile.
- **Workflows**: staging deploy triggers on `iac/**` path changes only. Production deploy is gated on the `production` branch. Dependabot PRs must skip the validate/plan jobs (`github.actor != 'dependabot[bot]'`).
- **E2e tests**: smoke tests in `iac/tests/e2e/` use `pytest.mark.skipif` to skip when `ALB_URL` is not set — this is intentional.

## Environments
- `staging`: deploys from `main` branch on tag push
- `production`: deploys from `production` branch, requires PR from `main`

## What to ignore
- `*.tfstate`, `*.tfstate.backup`, `.terraform/` — Terraform state, never committed
- `backend.hcl` — local backend config, gitignored
- `image_tags.*.tfvars` — updated by release workflow, not hand-edited
