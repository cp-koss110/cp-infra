#!/usr/bin/env bash
# bootstrap-local.sh
# Creates local AWS resources in LocalStack for development and integration testing.
#
# Usage (standalone):
#   LOCALSTACK_ENDPOINT=http://localhost:4566 ./scripts/bootstrap-local.sh
#
# Usage (via docker-compose):
#   docker-compose -f docker-compose.local.yml up -d
#   (the localstack-init service runs this script automatically)

set -euo pipefail

ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
REGION="${AWS_DEFAULT_REGION:-us-east-2}"
PROJECT="exam-costa"
ENV="local"

AWS="aws --endpoint-url=${ENDPOINT} --region=${REGION}"

echo "==> Bootstrapping LocalStack at ${ENDPOINT} for ${PROJECT}/${ENV}"

# ==========================================
# Wait for LocalStack to be ready
# ==========================================
echo "--> Waiting for LocalStack health..."
for i in $(seq 1 30); do
  if curl -sf "${ENDPOINT}/_localstack/health" > /dev/null 2>&1; then
    echo "    LocalStack is ready."
    break
  fi
  echo "    Attempt $i/30 — waiting 2s..."
  sleep 2
done

# ==========================================
# SQS Queues
# ==========================================
echo "--> Creating SQS queues..."

# Main messages queue
$AWS sqs create-queue \
  --queue-name "${PROJECT}-${ENV}-messages" \
  --attributes '{"VisibilityTimeout":"30","MessageRetentionPeriod":"86400"}' \
  --output text --query 'QueueUrl' \
  && echo "    Created: ${PROJECT}-${ENV}-messages"

# Dead-letter queue
$AWS sqs create-queue \
  --queue-name "${PROJECT}-${ENV}-messages-dlq" \
  --output text --query 'QueueUrl' \
  && echo "    Created: ${PROJECT}-${ENV}-messages-dlq"

# Integration test queue
$AWS sqs create-queue \
  --queue-name "${PROJECT}-test-messages" \
  --output text --query 'QueueUrl' \
  && echo "    Created: ${PROJECT}-test-messages"

# Worker integration test queue
$AWS sqs create-queue \
  --queue-name "${PROJECT}-worker-test-messages" \
  --output text --query 'QueueUrl' \
  && echo "    Created: ${PROJECT}-worker-test-messages"

# ==========================================
# S3 Buckets
# ==========================================
echo "--> Creating S3 buckets..."

# Main messages bucket
$AWS s3api create-bucket \
  --bucket "${PROJECT}-${ENV}-messages" \
  --create-bucket-configuration "LocationConstraint=${REGION}" \
  && echo "    Created: ${PROJECT}-${ENV}-messages"

# Worker integration test bucket
$AWS s3api create-bucket \
  --bucket "${PROJECT}-worker-test-bucket" \
  --create-bucket-configuration "LocationConstraint=${REGION}" \
  && echo "    Created: ${PROJECT}-worker-test-bucket"

# ==========================================
# SSM Parameters
# ==========================================
echo "--> Creating SSM parameters..."

# API token for local testing
$AWS ssm put-parameter \
  --name "/${PROJECT}/local/api/token" \
  --value "local-dev-token" \
  --type "SecureString" \
  --overwrite \
  && echo "    Created: /${PROJECT}/local/api/token"

# API token for integration tests
$AWS ssm put-parameter \
  --name "/${PROJECT}/test/api/token" \
  --value "integration-test-token" \
  --type "SecureString" \
  --overwrite \
  && echo "    Created: /${PROJECT}/test/api/token"

# Infrastructure output parameters (simulated)
SQS_URL="${ENDPOINT}/000000000000/${PROJECT}-${ENV}-messages"
$AWS ssm put-parameter \
  --name "/${PROJECT}/${ENV}/outputs/alb_url" \
  --value "http://localhost:8000" \
  --type "String" \
  --overwrite \
  && echo "    Created: /${PROJECT}/${ENV}/outputs/alb_url"

$AWS ssm put-parameter \
  --name "/${PROJECT}/${ENV}/outputs/sqs_queue_url" \
  --value "${SQS_URL}" \
  --type "String" \
  --overwrite \
  && echo "    Created: /${PROJECT}/${ENV}/outputs/sqs_queue_url"

$AWS ssm put-parameter \
  --name "/${PROJECT}/${ENV}/outputs/s3_bucket_name" \
  --value "${PROJECT}-${ENV}-messages" \
  --type "String" \
  --overwrite \
  && echo "    Created: /${PROJECT}/${ENV}/outputs/s3_bucket_name"

$AWS ssm put-parameter \
  --name "/${PROJECT}/${ENV}/outputs/ecs_cluster_name" \
  --value "${PROJECT}-${ENV}-cluster" \
  --type "String" \
  --overwrite \
  && echo "    Created: /${PROJECT}/${ENV}/outputs/ecs_cluster_name"

$AWS ssm put-parameter \
  --name "/${PROJECT}/${ENV}/outputs/api_service_name" \
  --value "${PROJECT}-${ENV}-api" \
  --type "String" \
  --overwrite \
  && echo "    Created: /${PROJECT}/${ENV}/outputs/api_service_name"

$AWS ssm put-parameter \
  --name "/${PROJECT}/${ENV}/outputs/worker_service_name" \
  --value "${PROJECT}-${ENV}-worker" \
  --type "String" \
  --overwrite \
  && echo "    Created: /${PROJECT}/${ENV}/outputs/worker_service_name"

echo ""
echo "==> Bootstrap complete!"
echo ""
echo "LocalStack resources created:"
echo "  SQS queues:      ${PROJECT}-${ENV}-messages, ${PROJECT}-${ENV}-messages-dlq"
echo "  S3 buckets:      ${PROJECT}-${ENV}-messages"
echo "  SSM parameters:  /${PROJECT}/local/api/token, /${PROJECT}/${ENV}/outputs/*"
echo ""
echo "Integration test env:"
echo "  export LOCALSTACK_ENDPOINT=${ENDPOINT}"
echo "  export SQS_QUEUE_URL=${SQS_URL}"
echo "  export S3_BUCKET_NAME=${PROJECT}-${ENV}-messages"
echo "  export SSM_PARAMETER_NAME=/${PROJECT}/local/api/token"
echo "  export AWS_ACCESS_KEY_ID=test"
echo "  export AWS_SECRET_ACCESS_KEY=test"
echo "  export AWS_DEFAULT_REGION=${REGION}"
