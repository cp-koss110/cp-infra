# Implementation Summary

## What Changed

This document describes all changes made to the `cp-infra/iac` repository as part of the DevOps exam implementation. See `/GAP_ANALYSIS.md` at the repo root for full gap analysis.

---

### Terraform Changes

#### `terraform/envs/eus2/variables.tf`
- **Fixed environment validation bug:** `contains(["test", "prod"], ...)` → `contains(["test", "staging", "prod", "dev"], ...)`
- **Added `api_image_tag` variable:** Per-service image tag override for the API (default `""`, falls back to `image_tag`)
- **Added `worker_image_tag` variable:** Per-service image tag override for the worker (default `""`, falls back to `image_tag`)

#### `terraform/envs/eus2/main.tf`
- **Updated locals block:** Added `resolved_api_tag` and `resolved_worker_tag` locals. ECR image URLs now use these resolved tags instead of `var.image_tag` directly.
- **Added SSM outputs resource:** `aws_ssm_parameter.infra_output` (for_each) writes six infrastructure values to SSM Parameter Store under `/{project_name}/{environment}/outputs/{key}`:
  - `alb_url`
  - `sqs_queue_url`
  - `s3_bucket_name`
  - `ecs_cluster_name`
  - `api_service_name`
  - `worker_service_name`

#### New tfvars files
- `terraform/envs/eus2/staging.tfvars` — staging environment config (`environment = "staging"`, `vpc_cidr = "10.2.0.0/16"`)
- `terraform/envs/eus2/image_tags.staging.tfvars` — managed by GitHub Actions, tracks current staging image tags
- `terraform/envs/eus2/image_tags.production.tfvars` — managed by GitHub Actions, tracks current production image tags

---

### GitHub Actions Workflows

Located in `cp-infra/.github/workflows/`:

| File | Trigger | Purpose |
|------|---------|---------|
| `staging-deploy.yml` | push to `main` | `terraform apply` with `staging.tfvars` |
| `production-checks.yml` | PR targeting `production` | fmt check, validate, plan, smoke tests |
| `production-deploy.yml` | push to `production` | `terraform apply` with `production.tfvars` |

---

### Local Development

#### `docker-compose.local.yml`
Starts LocalStack (S3, SQS, SSM, IAM, STS) and an init container that auto-runs `scripts/bootstrap-local.sh`.

```bash
make local-up       # Start LocalStack
make local-down     # Stop LocalStack
make local-bootstrap  # Re-seed resources
```

#### `scripts/bootstrap-local.sh`
Creates the following in LocalStack:
- SQS queues: `exam-costa-local-messages`, `exam-costa-local-messages-dlq`, test queues
- S3 buckets: `exam-costa-local-messages`, test bucket
- SSM parameters: `/exam-costa/local/api/token`, all six `/exam-costa/local/outputs/*`

---

### Tests

| Path | Purpose |
|------|---------|
| `tests/terraform/validate.sh` | `terraform fmt -check` + `terraform validate` |
| `tests/e2e/test_smoke.py` | HTTP smoke tests against deployed ALB |
| `tests/e2e/requirements.txt` | `pytest`, `requests` |

Run smoke tests:
```bash
export ALB_URL=http://your-alb-dns.us-east-2.elb.amazonaws.com
make test-e2e
```

---

## Required Secrets

### cp-infra GitHub repository secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user key for Terraform operations |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret for Terraform operations |
| `AWS_REGION` | AWS region (optional, defaults to `us-east-2`) |
| `TF_BACKEND_BUCKET` | S3 bucket name for Terraform remote state |
| `TF_LOCK_TABLE` | DynamoDB table name for state locking |
| `TF_VAR_API_TOKEN` | Value for the API Bearer token (written to SSM) |
| `STAGING_ALB_URL` | Fallback ALB URL used when SSM lookup fails in PR checks |

---

## Release Flow

### Standard release (tag-driven)

1. Developer pushes a semver tag to `cp-api` or `cp-worker` (e.g., `v1.2.3`)
2. Service repo `release.yml` workflow:
   - Builds and pushes Docker image to ECR with tag `v1.2.3`
   - Checks out `cp-infra` main branch
   - Updates `image_tags.staging.tfvars` (`api_image_tag = "v1.2.3"`)
   - Commits and pushes to `cp-infra` main
3. `cp-infra` `staging-deploy.yml` triggers on the new commit to main:
   - Runs `terraform apply` with `staging.tfvars` + `image_tags.staging.tfvars`
   - New image tag is deployed to ECS staging
4. Service repo release workflow opens a PR: `infra main → production`
5. PR triggers `production-checks.yml`:
   - Validates Terraform
   - Plans production changes
   - Posts plan output as PR comment
   - Runs smoke tests against staging
6. Reviewer merges the PR
7. `production-deploy.yml` runs `terraform apply` with `production.tfvars` + `image_tags.production.tfvars`

### Manual rollback / deploy specific tag (workflow_dispatch)

1. Go to `cp-api` or `cp-worker` → Actions → Release → Run workflow
2. Enter `image_tag` (e.g., `v1.1.0`) — build step is skipped
3. Optionally uncheck `open_pr` to update staging only without a production PR
4. Workflow updates `image_tags.staging.tfvars` and triggers staging deploy

---

## Branch Strategy

| Branch | Environment | Deploys via |
|--------|-------------|------------|
| `main` | staging | `staging-deploy.yml` on every push |
| `production` | production | `production-deploy.yml` on merge |
| PRs to `production` | (plan only) | `production-checks.yml` |

---

## Local Integration Testing

```bash
# Start LocalStack
make local-up

# Run API integration tests
cd cp-api
LOCALSTACK_ENDPOINT=http://localhost:4566 pytest tests/integration/ -v

# Run worker integration tests
cd cp-worker
LOCALSTACK_ENDPOINT=http://localhost:4566 pytest tests/integration/ -v

# Stop LocalStack
cd cp-infra/iac
make local-down
```
