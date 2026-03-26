# Makefile — exam-costa infra repo root
# Run from cp-infra/

.PHONY: help \
        local-up local-build local-down local-logs logs-api logs-worker logs-localstack \
        tf-init tf-plan-staging tf-apply-staging tf-plan-prod tf-apply-prod \
        app-test app-test-unit app-test-integration test-validate test-e2e \
        branch-protection \
        venv-clean

COMPOSE      := docker compose -f local/docker-compose.yml
TF_DIR       := iac/terraform/envs/eus2
GIT_SHA      := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
BUILD_DATE   := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
LOCAL_VERSION := local-$(GIT_SHA)

# ==========================================
help:
	@echo ""
	@echo "exam-costa — available targets"
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
	@echo "  Terraform:"
	@echo "    tf-init             terraform init (requires backend.hcl)"
	@echo "    tf-plan-staging     plan with staging.tfvars"
	@echo "    tf-apply-staging    apply staging (auto-approve)"
	@echo "    tf-plan-prod        plan with prod.tfvars"
	@echo "    tf-apply-prod       apply production (auto-approve)"
	@echo ""
	@echo "  App tests:"
	@echo "    app-test              run all unit tests (api + worker)"
	@echo "    app-test-unit         same as app-test"
	@echo "    app-test-integration  integration tests (requires LocalStack — make local-up first)"
	@echo "    venv-clean            remove .venv from cp-api and cp-worker"
	@echo ""
	@echo "  Infra tests:"
	@echo "    test-validate     terraform fmt-check + validate"
	@echo "    test-e2e          smoke tests (requires ALB_URL env var)"
	@echo ""
	@echo "  GitHub:"
	@echo "    branch-protection   apply branch protection rules to all 3 repos"
	@echo "                        (GITHUB_OWNER=koss110 by default)"
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

local-logs:
	$(COMPOSE) logs -f

logs-api:
	docker logs -f exam-costa-api

logs-worker:
	docker logs -f exam-costa-worker

logs-localstack:
	docker logs -f exam-costa-localstack

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

tf-plan-prod:
	cd $(TF_DIR) && terraform plan \
		-var-file=prod.tfvars \
		-var-file=image_tags.production.tfvars

tf-apply-prod:
	cd $(TF_DIR) && terraform apply \
		-var-file=prod.tfvars \
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

test-validate:
	./iac/tests/terraform/validate.sh

test-e2e:
	@if [ -z "$(ALB_URL)" ]; then \
		echo "ERROR: ALB_URL is not set. Export it first:"; \
		echo "  export ALB_URL=http://your-alb.us-east-2.elb.amazonaws.com"; \
		exit 1; \
	fi
	cd iac/tests/e2e && pip install -q -r requirements.txt && pytest -v
