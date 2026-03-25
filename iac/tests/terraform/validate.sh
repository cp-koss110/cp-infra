#!/usr/bin/env bash
# validate.sh
# Runs terraform fmt check and terraform validate against the eus2 environment.
#
# Usage:
#   ./tests/terraform/validate.sh
#   make test-validate

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${SCRIPT_DIR}/../../terraform/envs/eus2"
MODULES_DIR="${SCRIPT_DIR}/../../terraform/modules"

echo "==> Terraform Validation"
echo ""

# ==========================================
# Format check
# ==========================================
echo "--> Running: terraform fmt -check -recursive"
cd "${ENV_DIR}"
terraform fmt -check -recursive ../../
echo "    Format check passed."

# ==========================================
# Validate (requires init)
# ==========================================
echo "--> Running: terraform validate"
if [ ! -d "${ENV_DIR}/.terraform" ]; then
  echo "    .terraform directory not found — running terraform init first..."
  terraform init -backend=false
fi
terraform validate
echo "    Validate passed."

echo ""
echo "==> All checks passed."
