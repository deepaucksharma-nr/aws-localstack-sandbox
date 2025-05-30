# Enhanced Modular Database Monitoring Setup Guide

This guide explains how to use the enhanced modular setup that supports multiple database providers (containers, EC2, RDS, Aurora).

## Overview

The enhanced setup provides:
- **Multi-Provider Support**: Containers, EC2, RDS, and Aurora
- **Automatic Credential Resolution**: From AWS Secrets Manager, SSM, or environment variables
- **Configuration Transformation**: Converts between formats automatically
- **Database Discovery**: Find and monitor databases by AWS tags
- **Error Handling**: Validation and fix suggestions

## Quick Start

### 1. For RDS/Aurora Databases

```bash
# Discover existing databases
./scripts/discover-databases.py \
  --regions us-east-1 us-west-2 \
  --tag-filter monitor=newrelic \
  --output-file config/databases-discovered.yml

# Deploy monitoring with Terraform modules
cd terraform/environments/staging
terraform init
terraform apply -var="newrelic_license_key=YOUR_KEY"
```

### 2. For Container-Based Development

```bash
# Start containers with enhanced compose
docker-compose -f docker-compose-enhanced.yml up -d

# Test RDS simulation
./scripts/test-rds-simulation.sh
```

## Configuration Formats

### Enhanced Format (Recommended)

```yaml
mysql_databases:
  - name: "prod-mysql-rds"
    type: "mysql"
    provider: "rds"  # or "container", "ec2", "aurora"
    connection:
      endpoint: "mydb.abc123.rds.amazonaws.com"
      port: 3306
    credentials:
      username: "newrelic"
      password_source: "aws_secrets_manager"
      password_key: "/prod/mysql/password"
    monitoring:
      collect_rds_metrics: true
      enable_query_monitoring: true
    labels:
      environment: "production"
```

### Legacy Format (Still Supported)

```yaml
mysql_databases:
  - host: "mysql.example.com"
    port: 3306
    user: "newrelic"
    password: "plaintext_password"
```

## Credential Management

### 1. AWS Secrets Manager

```yaml
credentials:
  password_source: "aws_secrets_manager"
  password_key: "/prod/mysql/password"
```

Create secret:
```bash
aws secretsmanager create-secret \
  --name "/prod/mysql/password" \
  --secret-string "your-secure-password"
```

### 2. SSM Parameter Store

```yaml
credentials:
  password_source: "aws_ssm_parameter"
  password_key: "/prod/mysql/password"
```

Create parameter:
```bash
aws ssm put-parameter \
  --name "/prod/mysql/password" \
  --value "your-secure-password" \
  --type "SecureString"
```

### 3. Environment Variables

```yaml
credentials:
  password_source: "env_var"
  password_env: "MYSQL_PASSWORD"
```

## Deployment Flows

### Flow 1: Using Terraform Modules (Recommended for AWS)

1. **Choose Environment**:
   ```bash
   cd terraform/environments/production  # or staging/dev
   ```

2. **Configure Variables**:
   ```hcl
   # terraform.tfvars
   newrelic_license_key = "YOUR_LICENSE_KEY"
   aws_region = "us-east-1"
   ```

3. **Deploy Infrastructure**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

The modules will:
- Create RDS/Aurora instances with proper configuration
- Set up IAM roles with necessary permissions
- Configure security groups
- Create New Relic monitoring users automatically
- Store credentials in Secrets Manager
- Deploy monitoring instances with enhanced userdata

### Flow 2: Using Existing Databases

1. **Create Configuration**:
   ```bash
   cp config/databases-enhanced.example.yml config/databases.yml
   # Edit with your database details
   ```

2. **Validate Credentials**:
   ```bash
   ./scripts/validate-credentials.py config/databases.yml
   ```

3. **Deploy Monitoring**:
   ```bash
   ./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem
   ```

### Flow 3: Auto-Discovery

1. **Tag Your Databases**:
   ```bash
   aws rds add-tags-to-resource \
     --resource-name "arn:aws:rds:region:account:db:instance-name" \
     --tags Key=monitor,Value=newrelic
   ```

2. **Run Discovery**:
   ```bash
   ./scripts/discover-databases.py \
     --regions us-east-1 \
     --tag-filter monitor=newrelic \
     --output-file config/databases.yml
   ```

3. **Deploy**:
   ```bash
   ./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem
   ```

## Testing

### Local Testing with Containers

```bash
# Start test environment
docker-compose -f docker-compose-enhanced.yml up -d

# Run E2E tests
docker-compose -f docker-compose-enhanced.yml exec test-runner \
  python3 /workspace/test/integration/test_e2e_flow.py
```

### Test RDS Endpoints

```bash
# Start with RDS simulation profile
docker-compose -f docker-compose-enhanced.yml --profile rds-test up -d

# Test connections
./scripts/test-rds-simulation.sh
```

## Troubleshooting

### Credential Issues

```bash
# Validate all credentials
./scripts/validate-credentials.py config/databases.yml --fix

# This generates fix-credentials.sh with commands to resolve issues
./fix-credentials.sh
```

### Configuration Issues

```bash
# Test transformation
./scripts/transform-config.py \
  /tmp/database-config.json \
  /tmp/database-config.yml \
  --dry-run

# Check for errors in output
```

### Connection Issues

1. **Check Security Groups**:
   ```bash
   aws ec2 describe-security-groups --group-ids sg-xxxxx
   ```

2. **Test Connectivity**:
   ```bash
   nc -zv database-endpoint.region.rds.amazonaws.com 3306
   ```

3. **Verify IAM Permissions**:
   ```bash
   aws sts get-caller-identity
   aws secretsmanager get-secret-value --secret-id /prod/mysql/password
   ```

## Advanced Features

### Custom Metrics

Add custom queries to your configuration:

```yaml
monitoring:
  custom_metrics_query: |
    SELECT 
      COUNT(*) as active_connections,
      MAX(time) as max_query_time
    FROM information_schema.processlist
    WHERE command != 'Sleep'
```

### Multi-Region Setup

```bash
# Discover in multiple regions
./scripts/discover-databases.py \
  --regions us-east-1 us-west-2 eu-west-1 \
  --output-file config/databases-global.yml
```

### Aurora Global Databases

```yaml
- name: "global-aurora-cluster"
  provider: "aurora"
  connection:
    cluster_endpoint: "cluster.region1.rds.amazonaws.com"
    reader_endpoint: "cluster-ro.region1.rds.amazonaws.com"
  monitoring:
    monitor_readers: true
    collect_aurora_metrics: true
```

## Migration Guide

### From Basic to Enhanced Setup

1. **Update Terraform**:
   - Add IAM instance profile (already done in main.tf)
   - Use enhanced userdata template

2. **Convert Configuration**:
   ```bash
   # Old format → New format
   python3 scripts/migrate-config.py \
     config/databases.yml \
     config/databases-enhanced.yml
   ```

3. **Update Deployment**:
   - Use SSM parameter for configuration
   - Enable credential resolution

### From RDS to Aurora

1. **Use AWS DMS** or native tools for data migration
2. **Update configuration**:
   - Change provider from "rds" to "aurora"
   - Add cluster_endpoint and reader_endpoint
   - Enable aurora-specific metrics

## Best Practices

1. **Use Terraform Modules** for new deployments
2. **Store Credentials in AWS Secrets Manager** for production
3. **Enable Query Monitoring** for performance insights
4. **Use Tags** for auto-discovery
5. **Test Locally** with containers before deploying
6. **Validate Credentials** before deployment
7. **Monitor Multiple Regions** from a single instance

## Complete Example

```bash
# 1. Deploy Aurora cluster with monitoring
cd terraform/environments/production
terraform apply

# 2. Verify deployment
aws rds describe-db-clusters --db-cluster-identifier myapp-prod-mysql

# 3. Check monitoring
# Visit New Relic → Infrastructure → Databases

# 4. View query performance
# New Relic → Database → Query Analysis
```

The enhanced setup provides a complete, production-ready solution for monitoring databases across multiple providers with full automation.