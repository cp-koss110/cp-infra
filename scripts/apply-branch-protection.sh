#!/usr/bin/env bash
# apply-branch-protection.sh
# Applies branch protection rules to all three exam repos via the GitHub API.
#
# Usage:
#   ./scripts/apply-branch-protection.sh              # uses default owner: koss110
#   GITHUB_OWNER=other-user ./scripts/apply-branch-protection.sh
#
# Requires: gh CLI authenticated (gh auth status)
#
# Note: the following fields are org-only and are commented out below each block.
# Restore them when migrating to a GitHub organisation:
#   "require_code_owner_reviews": true
#   "bypass_pull_request_allowances": { "users": ["$OWNER"], "teams": ["dev-team"] }

set -euo pipefail

OWNER="${GITHUB_OWNER:-koss110}"
API="repos/$OWNER"
HEADER="Accept: application/vnd.github+json"

echo ""
echo "Applying branch protection rules (owner: $OWNER)"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# cp-api — main
# Required checks match job `name:` fields in .github/workflows/ci.yml
# ─────────────────────────────────────────────────────────────────────────────
echo "→ cp-api/main"
gh api "$API/cp-api/branches/main/protection" \
  --method PUT --header "$HEADER" --input - <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Lint",
      "Unit Tests",
      "Integration Tests (LocalStack)"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null
}
EOF
# Org-only — restore when migrating to a GitHub organisation:
#   inside "required_pull_request_reviews":
#     "require_code_owner_reviews": true,
#     "bypass_pull_request_allowances": { "users": ["$OWNER"], "teams": [] }

# ─────────────────────────────────────────────────────────────────────────────
# cp-worker — main
# ─────────────────────────────────────────────────────────────────────────────
echo "→ cp-worker/main"
gh api "$API/cp-worker/branches/main/protection" \
  --method PUT --header "$HEADER" --input - <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Lint",
      "Unit Tests",
      "Integration Tests (LocalStack)"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null
}
EOF
# Org-only — restore when migrating to a GitHub organisation:
#   inside "required_pull_request_reviews":
#     "require_code_owner_reviews": true,
#     "bypass_pull_request_allowances": { "users": ["$OWNER"], "teams": [] }

# ─────────────────────────────────────────────────────────────────────────────
# cp-infra — main
# No required status checks — automated image-tag commits are pushed directly
# by the release workflow using the owner PAT (bypasses rules via enforce_admins: false)
# ─────────────────────────────────────────────────────────────────────────────
echo "→ cp-infra/main"
gh api "$API/cp-infra/branches/main/protection" \
  --method PUT --header "$HEADER" --input - <<EOF
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null
}
EOF
# Org-only — restore when migrating to a GitHub organisation:
#   inside "required_pull_request_reviews":
#     "require_code_owner_reviews": true,
#     "bypass_pull_request_allowances": { "users": ["$OWNER"], "teams": [] }

# ─────────────────────────────────────────────────────────────────────────────
# cp-infra — production
# Required checks match job `name:` fields in production-checks.yml
# ─────────────────────────────────────────────────────────────────────────────
echo "→ cp-infra/production"
gh api "$API/cp-infra/branches/production/protection" \
  --method PUT --header "$HEADER" --input - <<EOF
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
    "dismiss_stale_reviews": true
  },
  "restrictions": null
}
EOF
# Org-only — restore when migrating to a GitHub organisation:
#   inside "required_pull_request_reviews":
#     "require_code_owner_reviews": true,
#     "bypass_pull_request_allowances": { "users": ["$OWNER"], "teams": [] }

echo ""
echo "Done. Summary:"
echo "  cp-api/main         — requires Lint + Unit Tests + Integration Tests + 1 review"
echo "  cp-worker/main      — requires Lint + Unit Tests + Integration Tests + 1 review"
echo "  cp-infra/main       — requires 1 review (no status checks — bot pushes bypass)"
echo "  cp-infra/production — requires all Terraform checks + 1 review"
echo ""
echo "Bypass: $OWNER (enforce_admins: false — owner is not subject to rules on personal repos)"
echo "Note:   require_code_owner_reviews + bypass_pull_request_allowances are org-only — see comments above"
