# cp-infra

![Staging Deploy](https://github.com/koss110/cp-infra/actions/workflows/staging-deploy.yml/badge.svg)
![Production Checks](https://github.com/koss110/cp-infra/actions/workflows/production-checks.yml/badge.svg)
![Production Deploy](https://github.com/koss110/cp-infra/actions/workflows/production-deploy.yml/badge.svg)
![Terraform](https://img.shields.io/badge/terraform-1.7-7B42BC)
![AWS](https://img.shields.io/badge/AWS-ECS%20Fargate-FF9900)

Terraform infrastructure, local development stack, and CI/CD orchestration for the DevOps Exam — Costa Paigin.

---

## Repositories

| Repo | Description |
|------|-------------|
| [`cp-api`](https://github.com/koss110/cp-api) | REST API — receives requests, validates token, publishes to SQS |
| [`cp-worker`](https://github.com/koss110/cp-worker) | Background worker — polls SQS, uploads messages to S3 |
| [`cp-infra`](https://github.com/koss110/cp-infra) | This repo — Terraform IaC + local stack + CI/CD workflows |

---

## System architecture

```mermaid
flowchart TD
    client([Client]) -->|POST /message| alb[ALB\nElastic Load Balancer]
    alb --> api[cp-api\nECS Fargate]
    api -->|GetParameter\nWithDecryption| ssm[(SSM Parameter Store\n/exam-costa/api/token)]
    api -->|SendMessage| sqs[(SQS Queue)]
    sqs -->|ReceiveMessage| worker[cp-worker\nECS Fargate]
    worker -->|PutObject| s3[(S3 Bucket\nmessages/YYYY/MM/DD/)]
    worker -->|DeleteMessage| sqs
    sqs -->|max retries exceeded| dlq[(SQS DLQ)]

    subgraph ecr[ECR]
        api_img[cp-api image]
        worker_img[cp-worker image]
    end

    api_img -.->|pull| api
    worker_img -.->|pull| worker
```

---

## CI/CD pipeline

```mermaid
flowchart TD
    tag[git tag vX.Y.Z\ncp-api or cp-worker] --> build[Build Docker image]
    build --> push[Push to ECR]
    push --> tfvars[Update image_tags\nstaging + production tfvars\nin cp-infra main]
    tfvars --> staging_deploy[staging-deploy.yml\nterraform apply]
    tfvars --> pr[Open / update PR\nmain → production]

    pr --> checks[production-checks.yml]
    checks --> validate[Terraform Validate\n& Format]
    checks --> plan[Terraform Plan\nposted as PR comment]
    checks --> smoke[Smoke Tests\nagainst staging ALB]

    pr -->|merge| prod_deploy[production-deploy.yml\nterraform apply]

    style staging_deploy fill:#2d6a4f,color:#fff
    style prod_deploy fill:#1b4332,color:#fff
    style checks fill:#264653,color:#fff
```

### Branch strategy

| Branch | Environment | Trigger |
|--------|------------|---------|
| `main` | Staging | Push to `main` with `iac/**` changes |
| `production` | Production | PR merged from `main` |

---

## Infrastructure overview

```mermaid
flowchart LR
    subgraph vpc[VPC 10.x.0.0/16]
        subgraph public[Public Subnets]
            alb[ALB]
            nat[NAT Gateway]
        end
        subgraph private[Private Subnets]
            api_task[cp-api\nFargate Task]
            worker_task[cp-worker\nFargate Task]
        end
    end

    igw[Internet Gateway] --> alb
    alb --> api_task
    api_task --> nat --> internet([AWS APIs\nSQS / SSM / ECR])
    worker_task --> nat
```

| Resource | Staging | Production |
|----------|---------|------------|
| ECS CPU | 256 (0.25 vCPU) | 256 (0.25 vCPU) |
| ECS Memory | 512 MB | 512 MB |
| NAT Gateways | 1 | 1 |
| S3 force-destroy | yes | no |
| Log retention | 7 days | 30 days |
| ECR tag mutability | MUTABLE | IMMUTABLE |

---

## Terraform state

| Environment | S3 key |
|-------------|--------|
| Staging | `envs/eus2/staging/terraform.tfstate` |
| Production | `envs/eus2/production/terraform.tfstate` |

State bucket: `exam-costa-terraform-state`
Lock table: `exam-costa-terraform-locks`

---

## Local development

### Prerequisites

- Docker + Docker Compose
- `make`
- AWS CLI (for inspecting LocalStack resources)

### Repo layout (siblings required)

```
parent-dir/
├── cp-infra/    ← this repo
├── cp-api/
└── cp-worker/
```

### Full local stack quickstart

```mermaid
flowchart LR
    ls[LocalStack\n:4566] -->|seeds| sqs_local[(SQS\nexam-costa-local-messages)]
    ls -->|seeds| s3_local[(S3\nexam-costa-local-messages)]
    ls -->|seeds| ssm_local[(SSM\n/exam-costa/local/api/token)]
    api_local[cp-api\n:8000] --> ls
    worker_local[cp-worker] --> ls
```

```bash
# Clone all three repos as siblings
git clone https://github.com/koss110/cp-infra
git clone https://github.com/koss110/cp-api
git clone https://github.com/koss110/cp-worker

cd cp-infra

# 1. Start LocalStack and seed AWS resources
make local-up

# 2. Build images and start the full stack (api + worker + localstack)
make local-build
```

**Verify:**
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
      "email_sender": "John Doe",
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

**Tear down:**
```bash
make local-down
```

---

## Make targets reference

### Bootstrap

| Target | Description |
|--------|-------------|
| `make bootstrap` | Create state bucket, ECR repos, DynamoDB lock table and write API token to SSM. Reads `API_TOKEN` from env var → `.env` file → interactive prompt (suggests `openssl rand -hex 32`) |

### Local stack

| Target | Description |
|--------|-------------|
| `make local-up` | Start LocalStack + seed SQS, S3, SSM (no app build) |
| `make local-build` | Build cp-api and cp-worker images + start full stack |
| `make local-down` | Stop all containers and remove volumes |
| `make local-logs` | Follow logs for all containers |
| `make logs-api` | Follow cp-api container logs |
| `make logs-worker` | Follow cp-worker container logs |
| `make logs-localstack` | Follow LocalStack container logs |

### Tests

| Target | Description |
|--------|-------------|
| `make app-test` | Unit tests for both services (with coverage) |
| `make app-test-unit` | Same as `app-test` |
| `make app-test-integration` | Integration tests — requires `LOCALSTACK_ENDPOINT=http://localhost:4566` |
| `make test-validate` | `terraform fmt -check` + `terraform validate` across all modules |
| `make test-e2e` | HTTP smoke tests — requires `ALB_URL=http://<alb-dns>` |

### Terraform

| Target | Description |
|--------|-------------|
| `make tf-init` | `terraform init` with S3 backend (requires local `backend.hcl`) |
| `make tf-plan-staging` | Plan staging with `staging.tfvars` + `image_tags.staging.tfvars` |
| `make tf-apply-staging` | Apply staging (auto-approve) |
| `make tf-plan-prod` | Plan production with `prod.tfvars` + `image_tags.production.tfvars` |
| `make tf-apply-prod` | Apply production (auto-approve) |

### GitHub

| Target | Description |
|--------|-------------|
| `make branch-protection` | Apply branch protection rules to all 3 repos |
| `make branch-protection-production` | Apply protection to `cp-infra/production` only |

### Nuke (destructive)

| Target | Description |
|--------|-------------|
| `make nuke-staging` | `terraform destroy` the staging environment |
| `make nuke-production` | `terraform destroy` the production environment |
| `make nuke-bootstrap` | Destroy ECR repos, state bucket, DynamoDB + delete API token from SSM |
| `make nuke-all` | Destroy everything — prompts for confirmation |

> `TF_BACKEND_BUCKET` and `TF_LOCK_TABLE` can be overridden via env var or `.env` file. Defaults to `exam-costa-terraform-state` / `exam-costa-terraform-locks`.

---

## Pre-commit hooks

### cp-infra (this repo)

Hooks run on every commit:

| Hook | What it checks |
|------|---------------|
| `trailing-whitespace` | No trailing whitespace |
| `end-of-file-fixer` | Files end with a newline |
| `check-yaml` | Valid YAML syntax |
| `check-json` | Valid JSON syntax |
| `check-merge-conflict` | No leftover conflict markers |
| `check-added-large-files` | No files > 500 KB |
| `terraform_fmt` | All `.tf` files are formatted (`terraform fmt`) |
| `detect-secrets` | No hardcoded secrets (`.tfvars` and lock files excluded) |

**Setup:**
```bash
pip install pre-commit==3.7.1
pre-commit install
```

**Run manually:**
```bash
pre-commit run --all-files
```

### cp-api / cp-worker

Additional hooks in the service repos:

| Hook | What it checks |
|------|---------------|
| `ruff` | Python lint |
| `ruff-format` | Python formatting |
| `unit tests (fast)` | Runs unit tests on every Python file commit |

**Setup (per service repo):**
```bash
make pre-commit-install   # installs hooks into .git/hooks
```

**Run manually:**
```bash
make pre-commit-run       # runs all hooks against all files
```

---

## First-time AWS deployment

### 1. Bootstrap

```bash
cd cp-infra
API_TOKEN=$(openssl rand -hex 32) make bootstrap
```

Bootstraps:
- S3 state bucket (`exam-costa-terraform-state`)
- DynamoDB lock table (`exam-costa-terraform-locks`)
- ECR repositories (`exam-costa-api`, `exam-costa-worker`)
- SSM SecureString at `/exam-costa/api/token`

### 2. Configure GitHub Actions secrets

Add these 4 secrets to **all three repos** (cp-api, cp-worker, cp-infra):

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM access key |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key |
| `INFRA_REPO_TOKEN` | Fine-grained PAT — cp-infra: contents + pull requests write |
| `INFRA_REPO` | `koss110/cp-infra` |

### 3. Push a tag to deploy

```bash
cd cp-api   && git tag v1.0.0 && git push --tags
cd cp-worker && git tag v1.0.0 && git push --tags
```

Staging deploys automatically. A PR to `production` is opened automatically.

### 4. Apply branch protection

```bash
cd cp-infra && make branch-protection
```

---

## Project structure

```
cp-infra/
├── iac/
│   ├── bootstrap/              # Run once — state bucket, ECR, lock table
│   ├── terraform/
│   │   ├── envs/eus2/          # Environment config
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── staging.tfvars
│   │   │   ├── prod.tfvars
│   │   │   ├── image_tags.staging.tfvars       # managed by GitHub Actions
│   │   │   └── image_tags.production.tfvars    # managed by GitHub Actions
│   │   └── modules/
│   │       ├── network/        # VPC, subnets, NAT, IGW
│   │       ├── alb/            # Load balancer + target group
│   │       ├── ecs_cluster/    # ECS cluster
│   │       ├── ecs_service/    # ECS task definition + service
│   │       ├── sqs/            # Queue + DLQ
│   │       ├── s3/             # Messages bucket
│   │       ├── iam/            # Execution + task roles
│   │       └── ssm_parameter/  # SSM parameter wrapper
│   └── tests/
│       ├── terraform/          # validate.sh — fmt-check + validate
│       └── e2e/                # test_smoke.py — HTTP smoke tests
├── local/
│   ├── docker-compose.yml      # Full local stack
│   └── scripts/
│       └── bootstrap-local.sh  # Seeds LocalStack
├── scripts/
│   └── apply-branch-protection.sh
└── Makefile
```
