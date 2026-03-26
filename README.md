# DevOps Exam — Costa (Constantin) Paigin

A two-microservice system built on AWS ECS Fargate, wired through SQS and S3, with a full GitHub Actions CI/CD pipeline and Terraform infrastructure-as-code.

---

## Repositories

| Repo | Description |
|------|-------------|
| `cp-api` | REST API — receives requests, validates token, publishes to SQS |
| `cp-worker` | Background worker — polls SQS, uploads messages to S3 |
| `cp-infra` | Terraform infrastructure + local dev stack + CI/CD orchestration |

---

## Architecture

```
Client
  │
  ▼
ALB (Elastic Load Balancer)
  │
  ▼
cp-api (ECS Fargate)          SSM Parameter Store
  │  validates token ◄──────────────────────────┘
  │
  ▼ publishes data (no token)
SQS Queue
  │
  ▼
cp-worker (ECS Fargate)
  │
  ▼
S3 Bucket  (messages/YYYY/MM/DD/<message-id>.json)
```

**Request payload (POST /message):**
```json
{
  "data": {
    "email_subject": "Happy new year!",
    "email_sender": "John doe",
    "email_timestream": "1693561101",
    "email_content": "Just want to say... Happy new year!!!"
  },
  "token": "<secret>"
}
```

The API validates:
- Token matches the value stored in SSM Parameter Store
- All 4 email fields are present and non-blank
- `email_timestream` is a valid numeric Unix timestamp

---

## Local Development

### Prerequisites

- Docker + Docker Compose
- `make`
- AWS CLI (for inspecting LocalStack resources)

### Quickstart

```bash
git clone <cp-infra-repo-url>
git clone <cp-api-repo-url>   # must be sibling of cp-infra
git clone <cp-worker-repo-url> # must be sibling of cp-infra

cd cp-infra

# Start LocalStack + seed SQS, S3, SSM
make local-up

# Build images and start the full stack
make local-build
```

**Verify the stack is up:**
```bash
curl http://localhost:8000/healthz
# {"status":"healthy","service":"api","version":"local-<sha>"}
```

**Send a test message:**
```bash
curl -s -X POST http://localhost:8000/message \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "email_subject": "Happy new year!",
      "email_sender": "John doe",
      "email_timestream": "1693561101",
      "email_content": "Just want to say... Happy new year!!!"
    },
    "token": "local-dev-token"
  }' | python3 -m json.tool
```

**Verify the worker uploaded it to S3:**
```bash
aws --endpoint-url=http://localhost:4566 --region us-east-2 \
  s3 ls s3://exam-costa-local-messages/messages/ --recursive
```

**Follow logs:**
```bash
make logs-api       # API container
make logs-worker    # Worker container
make local-logs     # All containers
```

**Tear down:**
```bash
make local-down
```

---

## Running Tests

### Unit tests (no dependencies)

```bash
# From cp-infra — runs both services
make test-unit

# Or per service
cd cp-api   && make test-unit
cd cp-worker && make test-unit
```

### Integration tests (requires LocalStack)

```bash
# Start LocalStack first
make local-up

# Then run
LOCALSTACK_ENDPOINT=http://localhost:4566 make test-integration
```

### Terraform validation

```bash
make test-validate   # terraform fmt -check + terraform validate
```

### End-to-end smoke tests (requires deployed ALB)

```bash
ALB_URL=http://<your-alb-dns> make test-e2e
```

---

## CI/CD Pipeline

### CI (on every push / PR)

Each service repo runs automatically:
1. `ruff` lint check
2. Unit tests with coverage report

### Release flow (triggered by git tag)

```
git tag v1.2.3 && git push --tags
```

1. **Build** — Docker image built with `VERSION=v1.2.3` baked in
2. **Push** — Image pushed to ECR as `exam-costa-api:v1.2.3`
3. **Staging** — `image_tags.staging.tfvars` updated in cp-infra → triggers `terraform apply` automatically
4. **PR opened** — `cp-infra main → production` PR opened automatically
5. **Production checks** — Terraform plan posted as PR comment + smoke tests run against staging
6. **Production deploy** — Merge the PR → `terraform apply` deploys to production

### Rollback

```bash
# Redeploy a previous tag without rebuilding
# Go to cp-api or cp-worker → Actions → Release → Run workflow
# Enter the old tag (e.g. v1.1.0) and uncheck "Open PR" to target staging only
```

---

## AWS Infrastructure (Terraform)

All resources are defined in `iac/terraform/envs/eus2/` and deployed per environment.

| Resource | Description |
|----------|-------------|
| ECS Cluster + Services | Runs cp-api and cp-worker as Fargate tasks |
| ALB | Receives traffic and routes to cp-api |
| SQS Queue + DLQ | Message queue between API and Worker |
| S3 Bucket | Stores processed messages at `messages/YYYY/MM/DD/<id>.json` |
| SSM Parameter Store | Holds API token + infrastructure output values |
| ECR | Docker image registries for both services |
| IAM | Task execution roles and task roles with least-privilege policies |

### Deploy to AWS

**1. Run bootstrap once** (creates S3 state bucket, DynamoDB lock table, ECR repos):
```bash
cd iac/bootstrap
terraform init
terraform apply
```

**2. Configure GitHub Actions secrets** in all three repos (see table below).

**3. Push a tag** to trigger the first build and deploy:
```bash
cd cp-api && git tag v1.0.0 && git push --tags
cd cp-worker && git tag v1.0.0 && git push --tags
```

**4. Apply infrastructure** (staging):
```bash
cd cp-infra
make tf-init
make tf-apply-staging
```

### Required GitHub Actions secrets

**cp-api and cp-worker:**

| Secret | Value |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | IAM credentials for ECR push |
| `AWS_SECRET_ACCESS_KEY` | IAM credentials for ECR push |
| `AWS_REGION` | `us-east-2` (or your region) |
| `INFRA_REPO_TOKEN` | GitHub PAT with write access to cp-infra |
| `INFRA_REPO` | `<org>/cp-infra` |

**cp-infra:**

| Secret | Value |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | IAM credentials for Terraform |
| `AWS_SECRET_ACCESS_KEY` | IAM credentials for Terraform |
| `AWS_REGION` | `us-east-2` |
| `TF_BACKEND_BUCKET` | S3 bucket name from bootstrap output |
| `TF_LOCK_TABLE` | DynamoDB table name from bootstrap output |
| `TF_VAR_API_TOKEN` | The secret token value for the API |
| `STAGING_ALB_URL` | ALB DNS after first `tf-apply-staging` |

---

## Make targets reference

```
# Local stack
make local-up          Start LocalStack + seed resources
make local-build       Build images + start full stack
make local-down        Stop everything and remove volumes
make local-logs        Follow all container logs
make logs-api          Follow API logs
make logs-worker       Follow Worker logs

# Tests
make test-unit         Unit tests for both services
make test-integration  Integration tests (requires LOCALSTACK_ENDPOINT)
make test-validate     Terraform fmt-check + validate
make test-e2e          Smoke tests (requires ALB_URL)

# Terraform
make tf-init           terraform init
make tf-plan-staging   Plan staging
make tf-apply-staging  Apply staging
make tf-plan-prod      Plan production
make tf-apply-prod     Apply production
```

---

## Project structure

```
cp-infra/
├── iac/
│   ├── bootstrap/          # Run once — state bucket, ECR, lock table
│   └── terraform/
│       └── envs/eus2/      # Main environment config (staging + prod)
│           ├── modules/    # network, alb, ecs, sqs, s3, iam, cicd
│           ├── staging.tfvars
│           ├── prod.tfvars
│           └── image_tags.*.tfvars   # managed by GitHub Actions
├── local/
│   ├── docker-compose.yml  # Full local stack
│   └── scripts/
│       └── bootstrap-local.sh  # Seeds LocalStack
└── Makefile

cp-api/
├── app/main.py             # FastAPI service
├── tests/
│   ├── test_main.py        # Unit tests
│   └── integration/        # LocalStack integration tests
└── Dockerfile

cp-worker/
├── app/worker.py           # SQS → S3 worker
├── tests/
│   ├── test_worker.py      # Unit tests
│   └── integration/        # LocalStack integration tests
└── Dockerfile
```
