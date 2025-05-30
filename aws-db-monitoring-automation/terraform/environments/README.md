# Environment-Specific Terraform Configurations

This directory contains environment-specific Terraform configurations for deploying the database monitoring infrastructure.

## Available Environments

### Development (`dev/`)
- Uses LocalStack for AWS service simulation
- Databases run as Docker containers
- Minimal infrastructure for local testing
- No RDS/Aurora instances

### Staging (`staging/`)
- Uses real AWS services
- RDS instances for MySQL and PostgreSQL
- Single NAT gateway to reduce costs
- Performance Insights disabled to save costs
- 7-day backup retention

### Production (`production/`)
- Full high-availability setup
- Aurora clusters for MySQL and PostgreSQL
- Multi-AZ deployments
- Performance Insights enabled
- 30-day backup retention
- Enhanced monitoring

## Usage

### Development Environment

```bash
cd terraform/environments/dev

# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply (with LocalStack running)
docker-compose up -d localstack
terraform apply
```

### Staging Environment

```bash
cd terraform/environments/staging

# Set up backend configuration
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "db-monitoring/staging/terraform.tfstate"
    region = "us-east-1"
  }
}
EOF

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var="newrelic_license_key=YOUR_LICENSE_KEY"

# Apply
terraform apply -var="newrelic_license_key=YOUR_LICENSE_KEY"
```

### Production Environment

```bash
cd terraform/environments/production

# Similar to staging, but with production-specific variables
terraform plan -var-file="production.tfvars"
terraform apply -var-file="production.tfvars"
```

## Environment Variables

Each environment supports the following variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for deployment | us-east-1 |
| `environment` | Environment name | (environment-specific) |
| `project_name` | Project name for resource naming | db-monitoring |
| `newrelic_license_key` | New Relic license key | (required) |

## Switching Between Environments

1. **Development to Staging**: 
   - Update database configuration from containers to RDS endpoints
   - Ensure New Relic agent can reach RDS instances
   - Update security groups for RDS access

2. **Staging to Production**:
   - Migrate from RDS to Aurora clusters
   - Enable Multi-AZ and read replicas
   - Increase backup retention
   - Enable Performance Insights

## Cost Optimization

### Development
- Uses LocalStack (free)
- t3.micro instances
- No RDS costs

### Staging
- Single NAT gateway
- t3.small RDS instances
- No Multi-AZ
- Performance Insights disabled

### Production
- Full redundancy with higher costs
- Consider Reserved Instances for long-term savings
- Use Aurora Serverless v2 for variable workloads

## Security Considerations

1. **Secrets Management**:
   - All passwords stored in AWS Secrets Manager
   - IAM roles with least privilege
   - No hardcoded credentials

2. **Network Security**:
   - Private subnets for databases
   - Security groups restrict access
   - VPC endpoints for AWS services

3. **Monitoring Access**:
   - New Relic users have read-only database access
   - Separate credentials per environment
   - Audit logs enabled

## Cleanup

To destroy resources in any environment:

```bash
terraform destroy
```

**Warning**: This will delete all resources including databases. Ensure you have backups if needed.