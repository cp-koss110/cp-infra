# Terraform Infrastructure as Code

Complete Terraform configuration for deploying the DevOps Exam microservices on AWS ECS Fargate.

## Architecture Overview

```
iac/terraform/
├── modules/              # Reusable Terraform modules
│   ├── network/         # VPC, Subnets, NAT Gateway, Routing
│   ├── iam/             # IAM Roles and Policies
│   ├── s3/              # S3 Buckets with encryption and lifecycle
│   ├── sqs/             # SQS Queues with DLQ
│   ├── ecr/             # ECR Docker repositories
│   ├── ssm_parameter/   # SSM Parameter Store
│   ├── alb/             # Application Load Balancer
│   ├── ecs_cluster/     # ECS Cluster configuration
│   └── ecs_service/     # ECS Services and Task Definitions
└── envs/
    └── eus2/            # US-East-2 environment
        ├── main.tf      # Root configuration (calls modules)
        ├── variables.tf # Input variables
        ├── outputs.tf   # Output values
        ├── backend.hcl.example         # S3 backend config template
        ├── test.tfvars.example         # Test environment values
        └── production.tfvars.example         # Production environment values
```

## Infrastructure Components

### Network Module
- **VPC**: Isolated network with DNS support
- **Public Subnets**: For ALB (internet-facing)
- **Private Subnets**: For ECS tasks (protected)
- **NAT Gateway**: Allows private subnets to access internet
- **Route Tables**: Proper routing for public and private traffic

### IAM Module
- **ECS Execution Role**: Pull images, write logs
- **API Task Role**: Access SSM parameters, send to SQS
- **Worker Task Role**: Read from SQS, write to S3

### S3 Module
- **Messages Bucket**: Store processed messages
- **Versioning**: Track object changes
- **Encryption**: Server-side encryption (AES256 or KMS)
- **Lifecycle Rules**: Auto-transition to cheaper storage classes

### SQS Module
- **Main Queue**: Message queue for API → Worker
- **Dead Letter Queue (DLQ)**: Failed message handling
- **Long Polling**: Reduce costs and latency
- **CloudWatch Alarms**: Monitor queue depth

### ECR Module
- **API Repository**: Docker images for API service
- **Worker Repository**: Docker images for Worker service
- **Image Scanning**: Vulnerability detection on push
- **Lifecycle Policy**: Keep last N images, delete old ones

### ALB Module
- **Load Balancer**: Internet-facing, HTTP/HTTPS
- **Target Group**: Route traffic to ECS tasks
- **Health Checks**: Ensure tasks are healthy
- **Listeners**: HTTP (port 80), optional HTTPS (port 443)

### ECS Cluster Module
- **ECS Cluster**: Container orchestration
- **Fargate Capacity Provider**: Serverless compute
- **Container Insights**: CloudWatch monitoring

### ECS Service Module
- **Task Definition**: Container specs (image, CPU, memory, env vars)
- **Service**: Maintain desired task count
- **CloudWatch Logs**: Centralized logging
- **Auto Scaling**: Scale based on CPU/memory (optional)

## Quick Start

### 1. Prerequisites

```bash
# Install tools
brew install terraform awscli jq

# Configure AWS credentials
aws configure

# Verify
terraform version  # >= 1.7.0
aws sts get-caller-identity
```

### 2. Create Backend Resources

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket exam-costa-terraform-state \
  --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket exam-costa-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket exam-costa-terraform-state \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name exam-costa-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-2
```

### 3. Configure Backend

```bash
cd iac/terraform/envs/eus2

# Copy backend configuration
cp backend.hcl.example backend.hcl
# Edit if needed (bucket name, table name, etc.)
```

### 4. Configure Variables

```bash
# For test environment
cp test.tfvars.example test.tfvars
vim test.tfvars  # Customize values

# For production environment
cp production.tfvars.example production.tfvars
vim production.tfvars  # Set production values
```

### 5. Initialize Terraform

```bash
terraform init -backend-config=backend.hcl
```

### 6. Deploy Infrastructure

```bash
# Test environment
terraform plan -var-file=test.tfvars -out=tfplan-test
terraform apply tfplan-test

# Production environment (with specific image tag)
terraform plan -var-file=production.tfvars -var="image_tag=v1.0.0" -out=tfplan-production
terraform apply tfplan-production
```

### 7. Verify Deployment

```bash
# Get outputs
terraform output

# Get ALB DNS name
terraform output -raw alb_dns_name

# Test API
curl http://$(terraform output -raw alb_dns_name)/health
```

## Using with Makefile

The project root has a Makefile with convenient commands:

```bash
# Initialize Terraform
make tf-init

# Validate configuration
make tf-validate

# Test with LocalStack (local AWS emulation)
make tf-validate-local

# Format code
make tf-fmt

# Plan deployment
make tf-plan ENV=test IMAGE_TAG=latest

# Apply deployment
make tf-apply ENV=test

# Show outputs
make tf-output

# Destroy infrastructure
make tf-destroy ENV=test
```

## Environment Variables

The following environment-specific variables should be set:

### Test Environment (`test.tfvars`)
- Minimal resources (1 task each, small CPU/memory)
- Single NAT Gateway (cost optimization)
- `force_destroy = true` for easy cleanup
- Shorter log retention (7 days)

### Production Environment (`production.tfvars`)
- High availability (2+ tasks, across multiple AZs)
- Multiple NAT Gateways (one per AZ)
- `force_destroy = false` (data protection)
- Longer log retention (30 days)
- Immutable ECR tags
- Specific semver image tags (e.g., `v1.0.0`)

## Module Usage Examples

### Using the Network Module

```hcl
module "network" {
  source = "../../modules/network"

  project_name = "my-project"
  environment  = "test"
  vpc_cidr     = "10.0.0.0/16"

  availability_zones   = ["us-east-2a", "us-east-2b"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = var.tags
}
```

### Using the ECS Service Module

```hcl
module "ecs_service_api" {
  source = "../../modules/ecs_service"

  service_name  = "my-api"
  cluster_id    = module.ecs_cluster.cluster_id
  desired_count = 2

  container_name  = "api"
  container_image = "123456789012.dkr.ecr.us-east-2.amazonaws.com/api:v1.0.0"
  container_port  = 8000

  cpu    = 256
  memory = 512

  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  security_groups = [aws_security_group.api.id]

  execution_role_arn = module.iam_ecs_execution_role.role_arn
  task_role_arn      = module.iam_api_task_role.role_arn

  target_group_arn = module.alb.target_group_arn

  environment_variables = {
    ENVIRONMENT = "production"
    API_PORT    = "8000"
  }

  log_retention_days = 30
  aws_region         = "us-east-2"

  tags = var.tags
}
```

## State Management

### Remote State (S3 + DynamoDB)
- **S3 Bucket**: Stores Terraform state files
- **Versioning**: Track state changes over time
- **Encryption**: State files are encrypted at rest
- **DynamoDB Table**: State locking prevents concurrent modifications

### Best Practices
1. **Never commit `*.tfstate` files** to Git
2. **Always use remote state** for team collaboration
3. **Enable state locking** to prevent conflicts
4. **Use workspaces** for multiple environments (optional)

## Security Best Practices

### Secrets Management
- ✅ Store secrets in SSM Parameter Store (SecureString)
- ✅ Never hardcode secrets in Terraform files
- ✅ Use IAM roles instead of access keys
- ✅ Change default tokens after deployment

### Network Security
- ✅ Private subnets for ECS tasks
- ✅ Security groups with least privilege
- ✅ NAT Gateway for outbound internet access
- ✅ No direct internet access to tasks

### Data Security
- ✅ S3 encryption at rest (AES256 or KMS)
- ✅ SQS encryption in transit and at rest
- ✅ CloudWatch Logs encryption
- ✅ Block all public S3 access

## Cost Optimization

### Test Environment
- Single NAT Gateway: ~$32/month
- Fargate tasks (2 × 0.25 vCPU, 512 MB): ~$15/month
- ALB: ~$22/month
- **Total**: ~$70/month

### Production Environment
- Multiple NAT Gateways: ~$96/month
- Fargate tasks (4 × 0.5 vCPU, 1 GB): ~$60/month
- ALB: ~$22/month
- **Total**: ~$180/month

### Cost Reduction Tips
1. Use single NAT Gateway in test
2. Use Fargate Spot for non-critical workloads
3. Enable S3 lifecycle rules
4. Set CloudWatch log retention
5. Use auto-scaling to match demand

## Troubleshooting

### Common Issues

#### Error: Backend initialization failed
```bash
# Solution: Ensure S3 bucket and DynamoDB table exist
aws s3 ls s3://exam-costa-terraform-state
aws dynamodb describe-table --table-name exam-costa-terraform-locks
```

#### Error: Module not found
```bash
# Solution: Run terraform init
terraform init -backend-config=backend.hcl
```

#### Error: Invalid image
```bash
# Solution: Build and push Docker images first
cd services/api && docker build -t api:latest .
# Push to ECR...
```

#### Error: Resource already exists
```bash
# Solution: Import existing resource or destroy it
terraform import aws_s3_bucket.example my-bucket
# OR
aws s3 rb s3://my-bucket --force
```

## GitHub Actions CI/CD (primary)

This Terraform configuration is deployed via GitHub Actions workflows in `.github/workflows/`:

| Workflow | Trigger | Action |
|----------|---------|--------|
| `staging-deploy.yml` | push to `main` | `terraform apply` with `staging.tfvars` + `image_tags.staging.tfvars` |
| `production-checks.yml` | PR targeting `production` | fmt-check, validate, plan (posted as PR comment), smoke tests |
| `production-deploy.yml` | push to `production` | `terraform apply` with `production.tfvars` + `image_tags.production.tfvars` |

### Per-service image tags

Image tags are tracked in separate var-files so the API and worker can be deployed independently:

```
terraform/envs/eus2/image_tags.staging.tfvars    # Updated by cp-api/cp-worker release workflows
terraform/envs/eus2/image_tags.production.tfvars # Updated when staging PR merges to production
```

Each file contains:
```hcl
api_image_tag    = "v1.2.3"
worker_image_tag = "v1.1.0"
```

These override `var.image_tag` for their respective service. When empty, they fall back to `var.image_tag`.

### Required GitHub secrets (cp-infra repo)

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM credentials for Terraform |
| `AWS_SECRET_ACCESS_KEY` | IAM credentials for Terraform |
| `TF_BACKEND_BUCKET` | S3 bucket for Terraform state |
| `TF_LOCK_TABLE` | DynamoDB table for state locking |
| `TF_VAR_API_TOKEN` | API Bearer token value for SSM |
| `STAGING_ALB_URL` | Fallback ALB URL for smoke tests |

## Legacy CodePipeline CI/CD

The original CodePipeline/CodeBuild setup remains in the Terraform modules and can be enabled via `enable_cicd = true` in tfvars. However, GitHub Actions is the recommended approach. See `IMPLEMENTATION_SUMMARY.md` for details.

## CI/CD Integration (other tools)

This Terraform configuration can also work with other CI/CD systems:

```groovy
// Jenkinsfile
stage('Terraform Plan') {
    steps {
        sh '''
            cd iac/terraform/envs/eus2
            terraform init -backend-config=backend.hcl
            terraform plan -var-file=${ENV}.tfvars -var="image_tag=${IMAGE_TAG}" -out=tfplan
        '''
    }
}

stage('Terraform Apply') {
    steps {
        sh '''
            cd iac/terraform/envs/eus2
            terraform apply tfplan
        '''
    }
}
```

## Maintenance

### Updating Infrastructure

```bash
# 1. Pull latest code
git pull origin main

# 2. Review changes
terraform plan -var-file=test.tfvars

# 3. Apply if safe
terraform apply -var-file=test.tfvars

# 4. Verify
terraform output
make smoke-test
```

### Destroying Infrastructure

```bash
# Test environment (safe)
terraform destroy -var-file=test.tfvars -auto-approve

# Production (requires confirmation)
terraform destroy -var-file=production.tfvars
```

### Migrating State

```bash
# Pull current state
terraform state pull > backup.tfstate

# Update backend configuration
vim backend.hcl

# Migrate state
terraform init -migrate-state -backend-config=backend.hcl
```

## Additional Resources

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [ECS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## Support

For issues or questions:
1. Check the main `README.md` in project root
2. Review `docs/ARCHITECTURE.md` for design decisions
3. Check CloudWatch logs for runtime errors
4. Review Terraform state for resource details
