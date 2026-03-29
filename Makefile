# Makefile — exam-costa infra repo root
# Run from cp-infra/

.PHONY: help \
        bootstrap \
        local-up local-build local-down local-logs logs-api logs-worker logs-localstack \
        local-monitoring-up local-monitoring-down logs-monitoring \
        tf-init tf-plan-staging tf-apply-staging tf-plan-production tf-apply-production \
        app-test app-test-unit app-test-integration test-validate test-e2e install-e2e \
        branch-protection branch-protection-production update-aws-secrets \
        nuke-staging nuke-production nuke-bootstrap nuke-all \
        venv-clean

PROJECT_NAME  := $(or $(PROJECT_NAME),exam-costa)
GITHUB_OWNER  := $(or $(GITHUB_OWNER),koss110)

BOOTSTRAP_DIR := iac/bootstrap
COMPOSE            := docker compose -f local/docker-compose.yml
COMPOSE_MONITORING := docker compose -f local/docker-compose.monitoring.yml
TF_DIR       := iac/terraform/envs/eus2
GIT_SHA      := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
BUILD_DATE   := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
LOCAL_VERSION := local-$(GIT_SHA)

TF_BACKEND_BUCKET := $(or $(TF_BACKEND_BUCKET),$(shell grep '^TF_BACKEND_BUCKET=' .env 2>/dev/null | cut -d= -f2-),$(PROJECT_NAME)-terraform-state)
TF_LOCK_TABLE     := $(or $(TF_LOCK_TABLE),$(shell grep '^TF_LOCK_TABLE=' .env 2>/dev/null | cut -d= -f2-),$(PROJECT_NAME)-terraform-locks)

E2E_ENV    := $(or $(ENV),staging)
E2E_DIR    := iac/tests/e2e
E2E_VENV   := $(E2E_DIR)/.venv
E2E_PYTEST := $(E2E_VENV)/bin/pytest

# ==========================================
# Bootstrap (run once before first deploy)
# ==========================================

# Resolve the API token from: env var → .env file → interactive prompt.
# The token is written to SSM as a SecureString so it never enters Terraform state.
define get_api_token
$(shell \
	if [ -n "$$API_TOKEN" ]; then \
		echo "$$API_TOKEN"; \
	elif [ -f .env ] && grep -q '^API_TOKEN=' .env; then \
		grep '^API_TOKEN=' .env | cut -d= -f2-; \
	else \
		printf "Enter API token (will be stored in SSM as SecureString; or run: openssl rand -hex 32): " >&2; \
		read -r token; \
		echo "$$token"; \
	fi \
)
endef

bootstrap:
	@echo ""
	@echo "==> Running Terraform bootstrap..."
	cd $(BOOTSTRAP_DIR) && terraform init
	cd $(BOOTSTRAP_DIR) && terraform apply -auto-approve
	@echo ""
	@echo "==> Writing API token to SSM (staging + production)..."
	$(eval TOKEN := $(call get_api_token))
	@if [ -z "$(TOKEN)" ]; then \
		echo "ERROR: API_TOKEN is empty. Aborting."; exit 1; \
	fi
	@aws ssm put-parameter \
		--name "/$(PROJECT_NAME)/staging/api/token" \
		--value "$(TOKEN)" \
		--type SecureString \
		--region us-east-2 \
		--overwrite \
		--description "API auth token for $(PROJECT_NAME) (staging)" \
		> /dev/null
	@aws ssm put-parameter \
		--name "/$(PROJECT_NAME)/production/api/token" \
		--value "$(TOKEN)" \
		--type SecureString \
		--region us-east-2 \
		--overwrite \
		--description "API auth token for $(PROJECT_NAME) (production)" \
		> /dev/null
	@echo "    Tokens written to SSM: staging + production."
	@echo ""
	@echo "Bootstrap complete. Next steps:"
	@echo "  1. Copy backend config:  cp $(BOOTSTRAP_DIR)/../terraform/envs/eus2/backend.hcl.example $(BOOTSTRAP_DIR)/../terraform/envs/eus2/backend.hcl"
	@echo "  2. Push a tag to cp-api and cp-worker to trigger the first ECR build + staging deploy"
	@echo "  3. Run 'make branch-protection' to apply GitHub branch rules"
	@echo ""

# ==========================================
help:
	@echo ""
	@echo "$(PROJECT_NAME) — available targets"
	@echo ""
	@echo "  Bootstrap (run once):"
	@echo "    bootstrap     Create state bucket, ECR repos, DynamoDB lock table + write API token to SSM"
	@echo "                  Reads API_TOKEN from env var, .env file, or interactive prompt"
	@echo ""
	@echo "  Local stack:"
	@echo "    local-up      Start LocalStack + seed resources (no app build)"
	@echo "    local-build   Build images + start full stack (api, worker, localstack)"
	@echo "    local-down    Stop and remove all containers and volumes"
	@echo "    local-logs    Follow logs for all services"
	@echo "    logs-api      Follow API container logs"
	@echo "    logs-worker   Follow Worker container logs"
	@echo "    logs-localstack  Follow LocalStack logs"
	@echo ""
	@echo "  Local monitoring (optional):"
	@echo "    local-monitoring-up    Start Prometheus + Grafana + Node Exporter"
	@echo "    local-monitoring-down  Stop monitoring stack"
	@echo "    logs-monitoring        Follow all monitoring container logs"
	@echo "    logs-grafana           Follow Grafana logs"
	@echo "    logs-prometheus        Follow Prometheus logs"
	@echo "    Grafana:    http://localhost:3000  (admin/grafana)"
	@echo "    Prometheus: http://localhost:9090"
	@echo ""
	@echo "  Terraform:"
	@echo "    tf-init             terraform init (requires backend.hcl)"
	@echo "    tf-plan-staging     plan with staging.tfvars"
	@echo "    tf-apply-staging    apply staging (auto-approve)"
	@echo "    tf-plan-production        plan with production.tfvars"
	@echo "    tf-apply-production       apply production (auto-approve)"
	@echo ""
	@echo "  App tests:"
	@echo "    app-test              run all unit tests (api + worker)"
	@echo "    app-test-unit         same as app-test"
	@echo "    app-test-integration  integration tests (requires LocalStack — make local-up first)"
	@echo "    venv-clean            remove .venv from cp-api and cp-worker"
	@echo ""
	@echo "  Infra tests:"
	@echo "    test-validate          terraform fmt-check + validate"
	@echo "    install-e2e            create venv + install e2e test dependencies"
	@echo "    test-e2e               smoke tests — ALB_URL auto-fetched from SSM (staging)"
	@echo "    test-e2e ENV=production smoke tests against production ALB"
	@echo "    test-e2e ALB_URL=http://... override ALB_URL manually"
	@echo ""
	@echo "  GitHub:"
	@echo "    branch-protection              apply branch protection rules to all 3 repos"
	@echo "    branch-protection-production   apply protection to cp-infra/production only"
	@echo "    update-aws-secrets             rotate AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY"
	@echo "                                   across cp-api, cp-worker, cp-infra (prompts for values)"
	@echo "                                   (GITHUB_OWNER=koss110 by default)"
	@echo ""
	@echo "  Nuke (DESTRUCTIVE — destroys real AWS resources):"
	@echo "    nuke-staging        Destroy the staging Terraform environment"
	@echo "    nuke-production     Destroy the production Terraform environment"
	@echo "    nuke-bootstrap      Destroy ECR repos, state bucket, DynamoDB + delete API token"
	@echo "    nuke-all            Destroy everything — asks for confirmation first"
	@echo ""

# ==========================================
# Local stack
# ==========================================

local-up:
	$(COMPOSE) up -d localstack localstack-init
	@echo ""
	@echo "LocalStack is starting at http://localhost:4566"
	@echo "Run 'make local-build' to also start the api and worker."

local-build:
	LOCAL_VERSION=$(LOCAL_VERSION) BUILD_DATE=$(BUILD_DATE) VCS_REF=$(GIT_SHA) $(COMPOSE) up --build -d
	@echo ""
	@echo "Stack is up:"
	@echo "  API    -> http://localhost:8000"
	@echo "  API health -> http://localhost:8000/healthz"
	@echo "  LocalStack -> http://localhost:4566/_localstack/health"

local-down:
	$(COMPOSE) down -v

local-monitoring-up:
	$(COMPOSE_MONITORING) up -d
	@echo "Waiting for Grafana to be ready..."
	@for i in $$(seq 1 30); do \
		curl -sf http://localhost:3000/api/health > /dev/null 2>&1 && break; \
		sleep 2; \
	done
	@echo ""
	@echo "Monitoring stack is up:"
	@echo "  Grafana:    http://localhost:3000  (admin / grafana)"
	@echo "  Prometheus: http://localhost:9090"
	@echo "  Node Exp:   http://localhost:9100/metrics"
	@echo ""
	@echo "Node Exporter Full dashboard is pre-loaded — open Grafana and it will be on the home screen."

local-monitoring-down:
	$(COMPOSE_MONITORING) down -v

local-logs:
	$(COMPOSE) logs -f

logs-monitoring:
	$(COMPOSE_MONITORING) logs -f

logs-api:
	docker logs -f $(PROJECT_NAME)-api

logs-worker:
	docker logs -f $(PROJECT_NAME)-worker

logs-localstack:
	docker logs -f $(PROJECT_NAME)-localstack

logs-grafana:
	docker logs -f $(PROJECT_NAME)-grafana

logs-prometheus:
	docker logs -f $(PROJECT_NAME)-prometheus

# ==========================================
# Terraform
# ==========================================

tf-init:
	cd $(TF_DIR) && terraform init -backend-config=backend.hcl

tf-plan-staging:
	cd $(TF_DIR) && terraform plan \
		-var-file=staging.tfvars \
		-var-file=image_tags.staging.tfvars

tf-apply-staging:
	cd $(TF_DIR) && terraform apply \
		-var-file=staging.tfvars \
		-var-file=image_tags.staging.tfvars \
		-auto-approve

tf-plan-production:
	cd $(TF_DIR) && terraform plan \
		-var-file=production.tfvars \
		-var-file=image_tags.production.tfvars

tf-apply-production:
	cd $(TF_DIR) && terraform apply \
		-var-file=production.tfvars \
		-var-file=image_tags.production.tfvars \
		-auto-approve

# ==========================================
# Tests
# ==========================================

app-test: app-test-unit

app-test-unit:
	$(MAKE) -C ../cp-api    test-unit
	$(MAKE) -C ../cp-worker test-unit

app-test-integration:
	@if [ -z "$(LOCALSTACK_ENDPOINT)" ]; then \
		echo "ERROR: LOCALSTACK_ENDPOINT is not set."; \
		echo "  Run: make local-up  (then wait ~10s for LocalStack to be ready)"; \
		echo "  Then: LOCALSTACK_ENDPOINT=http://localhost:4566 make app-test-integration"; \
		exit 1; \
	fi
	$(MAKE) -C ../cp-api    test-integration LOCALSTACK_ENDPOINT=$(LOCALSTACK_ENDPOINT)
	$(MAKE) -C ../cp-worker test-integration LOCALSTACK_ENDPOINT=$(LOCALSTACK_ENDPOINT)

venv-clean:
	$(MAKE) -C ../cp-api    venv-clean
	$(MAKE) -C ../cp-worker venv-clean

branch-protection:
	@bash scripts/apply-branch-protection.sh

branch-protection-production:
	@echo ""
	@echo "→ cp-infra/production"
	@gh api "repos/${GITHUB_OWNER:-koss110}/cp-infra/branches/production/protection" \
	  --method PUT \
	  --header "Accept: application/vnd.github+json" \
	  --input - <<'EOF'
	{
	  "required_status_checks": {
	    "strict": true,
	    "contexts": [
	      "Terraform Validate & Format",
	      "Terraform Plan — Production",
	      "Smoke Tests — Staging"
	    ]
	  },
	  "enforce_admins": false,
	  "required_pull_request_reviews": {
	    "required_approving_review_count": 1,
	    "dismiss_stale_reviews": true,
	    "require_code_owner_reviews": true,
	    "bypass_pull_request_allowances": {
	      "users": ["${GITHUB_OWNER:-koss110}"],
	      "teams": []
	    }
	  },
	  "restrictions": null
	}
	EOF
	@echo "Done — cp-infra/production requires: Terraform Validate & Format + Terraform Plan + Smoke Tests + 1 review"
	@echo ""

update-aws-secrets:
	@echo ""
	@echo "==> Updating AWS credentials in GitHub Actions secrets (all 3 repos)..."
	@echo "    Repos: $(GITHUB_OWNER)/cp-api, $(GITHUB_OWNER)/cp-worker, $(GITHUB_OWNER)/cp-infra"
	@echo ""
	@printf "Enter AWS_ACCESS_KEY_ID: "; read -r AWS_KEY_ID; \
	printf "Enter AWS_SECRET_ACCESS_KEY: "; read -rs AWS_SECRET_KEY; echo ""; \
	if [ -z "$$AWS_KEY_ID" ] || [ -z "$$AWS_SECRET_KEY" ]; then \
		echo "ERROR: Both values are required. Aborted."; exit 1; \
	fi; \
	for repo in cp-api cp-worker cp-infra; do \
		echo "  → $(GITHUB_OWNER)/$$repo"; \
		gh secret set AWS_ACCESS_KEY_ID     --body "$$AWS_KEY_ID"     --repo $(GITHUB_OWNER)/$$repo; \
		gh secret set AWS_SECRET_ACCESS_KEY --body "$$AWS_SECRET_KEY" --repo $(GITHUB_OWNER)/$$repo; \
	done
	@echo ""
	@echo "Done. AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY updated in all 3 repos."
	@echo ""

test-validate:
	./iac/tests/terraform/validate.sh

$(E2E_VENV)/bin/activate: $(E2E_DIR)/requirements.txt
	python3 -m venv $(E2E_VENV)
	$(E2E_VENV)/bin/pip install -q -r $(E2E_DIR)/requirements.txt
	touch $(E2E_VENV)/bin/activate

install-e2e: $(E2E_VENV)/bin/activate

test-e2e: install-e2e
	@[ -n "$$ALB_URL" ] && _ALB_URL="$$ALB_URL" || \
		_ALB_URL=$$(aws ssm get-parameter \
			--name "/$(PROJECT_NAME)/$(E2E_ENV)/outputs/alb_url" \
			--query "Parameter.Value" --output text --region us-east-2 2>/dev/null) || true; \
	[ -n "$$S3_BUCKET_NAME" ] && _S3_BUCKET="$$S3_BUCKET_NAME" || \
		_S3_BUCKET=$$(aws ssm get-parameter \
			--name "/$(PROJECT_NAME)/$(E2E_ENV)/outputs/s3_bucket_name" \
			--query "Parameter.Value" --output text --region us-east-2 2>/dev/null) || true; \
	[ -n "$$API_TOKEN" ] && _API_TOKEN="$$API_TOKEN" || \
		_API_TOKEN=$$(aws ssm get-parameter \
			--name "/$(PROJECT_NAME)/$(E2E_ENV)/api/token" \
			--with-decryption \
			--query "Parameter.Value" --output text --region us-east-2 2>/dev/null) || true; \
	if [ -z "$$_ALB_URL" ]; then \
		echo "ERROR: Could not resolve ALB_URL from SSM (/$(PROJECT_NAME)/$(E2E_ENV)/outputs/alb_url)."; \
		echo "  Ensure AWS credentials are set, or pass ALB_URL=http://... explicitly."; \
		exit 1; \
	fi; \
	echo "==> Running smoke tests against [$$_ALB_URL] ($(E2E_ENV))"; \
	PROJECT_NAME=$(PROJECT_NAME) \
	E2E_ENV=$(E2E_ENV) \
	ALB_URL="$$_ALB_URL" \
	S3_BUCKET_NAME="$$_S3_BUCKET" \
	API_TOKEN="$$_API_TOKEN" \
	AWS_REGION=us-east-2 \
	$(E2E_PYTEST) $(E2E_DIR) -v

# ==========================================
# Nuke (destroy) — DESTRUCTIVE
# Fetch the API token from SSM for the destroy plan so Terraform
# can resolve all variables without prompting.
# ==========================================

nuke-staging:
	@echo ""
	@echo "==> Destroying STAGING environment..."
	cd $(TF_DIR) && \
		printf 'bucket         = "$(TF_BACKEND_BUCKET)"\nkey            = "envs/eus2/staging/terraform.tfstate"\nregion         = "us-east-2"\ndynamodb_table = "$(TF_LOCK_TABLE)"\nencrypt        = true\n' > /tmp/nuke-staging.hcl && \
		terraform init -backend-config=/tmp/nuke-staging.hcl -reconfigure && \
		terraform destroy \
			-var-file=staging.tfvars \
			-var-file=image_tags.staging.tfvars \
			-auto-approve

nuke-production:
	@echo ""
	@echo "==> Destroying PRODUCTION environment..."
	cd $(TF_DIR) && \
		printf 'bucket         = "$(TF_BACKEND_BUCKET)"\nkey            = "envs/eus2/production/terraform.tfstate"\nregion         = "us-east-2"\ndynamodb_table = "$(TF_LOCK_TABLE)"\nencrypt        = true\n' > /tmp/nuke-production.hcl && \
		terraform init -backend-config=/tmp/nuke-production.hcl -reconfigure && \
		terraform destroy \
			-var-file=production.tfvars \
			-var-file=image_tags.production.tfvars \
			-auto-approve

nuke-bootstrap:
	@echo ""
	@echo "==> Removing API tokens from SSM..."
	@aws ssm delete-parameter --name "/$(PROJECT_NAME)/staging/api/token" \
		--region us-east-2 2>/dev/null && echo "    Staging token deleted." || echo "    Staging token not found, skipping."
	@aws ssm delete-parameter --name "/$(PROJECT_NAME)/production/api/token" \
		--region us-east-2 2>/dev/null && echo "    Production token deleted." || echo "    Production token not found, skipping."
	@echo "==> Destroying BOOTSTRAP resources (ECR, S3 state bucket, DynamoDB)..."
	cd $(BOOTSTRAP_DIR) && terraform destroy -auto-approve

nuke-all:
	@echo ""
	@echo "+------------------------------------------------------+"
	@echo "|  WARNING: This will destroy ALL AWS resources:       |"
	@echo "|    - Staging/Production ECS, ALB, SQS, S3, SSM      |"
	@echo "|    - ECR repositories (all images will be lost)      |"
	@echo "|    - Terraform state bucket and lock table           |"
	@echo "+------------------------------------------------------+"
	@echo ""
	@printf "Type 'yes' to confirm: "; read -r confirm; \
	if [ "$$confirm" != "yes" ]; then echo "Aborted."; exit 1; fi
	$(MAKE) nuke-staging
	$(MAKE) nuke-bootstrap
