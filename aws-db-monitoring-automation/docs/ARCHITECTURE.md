# Architecture & Developer Experience

## How New Relic Uses LocalStack to Simplify Database Monitoring Setup

At New Relic, we understand that setting up comprehensive database monitoring can be complex and time-consuming. That's why we've built this reference implementation using LocalStack, Terraform, and Ansible to provide a complete end-to-end automated setup that dramatically improves the developer experience.

## The Developer Experience Challenge

Traditional database monitoring setup requires:
- Manually provisioning infrastructure
- Complex network configuration
- Installing and configuring agents
- Setting up credentials and permissions
- Testing in production (risky!)
- Hours or days of implementation time

## Our Solution: LocalStack-Powered Automation

```
LocalStack Testing → Terraform Automation → Ansible Configuration → Production Ready
```

### 1. Risk-Free Local Development with LocalStack

We use LocalStack Community Edition (free) to provide a complete AWS environment on your laptop:

```bash
# Start a full AWS environment locally
make start

# Test the entire setup without spending a penny
make test

# Iterate quickly and safely
make stop
```

**Developer Benefits:**
- **Zero AWS costs during development** - Test as much as you want
- **Fast iteration** - No waiting for AWS resources to provision
- **Safe experimentation** - Break things without consequences
- **Identical workflow** - Same Terraform/Ansible code works in production

### 2. Infrastructure as Code with Terraform

Our Terraform modules provide:
```hcl
# One command to create everything
terraform apply

# Creates:
# - EC2 monitoring instance
# - Security groups with correct rules
# - IAM roles and policies
# - Network configuration
# - All AWS resources needed
```

**Developer Benefits:**
- **Reproducible deployments** - Same result every time
- **Version controlled** - Track all infrastructure changes
- **Modular design** - Use only what you need
- **Multi-region ready** - Deploy anywhere

### 3. Configuration Management with Ansible

Ansible handles all the complex configuration:
```yaml
# Automatically:
# - Installs New Relic Infrastructure agent
# - Configures database integrations
# - Sets up query monitoring
# - Manages credentials securely
# - Applies best practices
```

**Developer Benefits:**
- **No manual SSH needed** - Fully automated
- **Idempotent** - Run multiple times safely
- **Template-driven** - Easy to customize
- **Battle-tested** - Based on thousands of deployments

## The Complete Developer Workflow

### Day 1: From Zero to Monitoring

```bash
# 1. Clone and configure (2 minutes)
git clone https://github.com/newrelic/aws-db-monitoring-automation
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp config/databases.example.yml config/databases.yml

# 2. Test locally with LocalStack (5 minutes)
make test  # Runs complete test suite

# 3. Deploy to AWS (5 minutes)
./scripts/deploy-monitoring.sh -k ~/.ssh/key.pem

# Total time: ~12 minutes to production monitoring
```

### Continuous Development

```bash
# Make changes to configuration
vim config/databases.yml

# Test changes locally first
docker-compose up -d
make test-integration

# Apply to production
ansible-playbook -i inventory/hosts.yml playbooks/update-config.yml
```

## LocalStack Integration Details

### What We Test with LocalStack

1. **AWS Resource Creation**
   ```python
   # Automated tests verify:
   - VPC and subnet creation
   - Security group rules
   - EC2 instance provisioning
   - IAM role policies
   - SSM parameter storage
   - Secrets Manager integration
   ```

2. **Integration Testing**
   ```python
   # End-to-end tests ensure:
   - Agent can connect to databases
   - Metrics are collected properly
   - Configuration is applied correctly
   - Network connectivity works
   ```

3. **Failure Scenarios**
   ```python
   # We test edge cases:
   - Database connection failures
   - Permission issues
   - Network timeouts
   - Configuration errors
   ```

### LocalStack Services Used

All services are available in the free Community Edition:
- **EC2**: Instance provisioning and management
- **IAM**: Role and policy creation
- **VPC**: Network infrastructure
- **SSM**: Parameter store for configuration
- **Secrets Manager**: Secure credential storage

## Architecture Components

### Monitoring Infrastructure
```
┌─────────────────────────────────────────────┐
│             Your AWS Account                 │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │         VPC (10.0.0.0/16)          │   │
│  │                                     │   │
│  │  ┌────────────────────────────┐    │   │
│  │  │   Monitoring Instance       │    │   │
│  │  │   - New Relic Agent        │    │   │
│  │  │   - MySQL Integration      │    │   │
│  │  │   - PostgreSQL Integration │    │   │
│  │  └────────────┬───────────────┘    │   │
│  │               │                     │   │
│  │  ┌────────────▼───────────────┐    │   │
│  │  │   Your Databases           │    │   │
│  │  │   - RDS MySQL              │    │   │
│  │  │   - RDS PostgreSQL         │    │   │
│  │  │   - Aurora Clusters        │    │   │
│  │  └────────────────────────────┘    │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
                      │
                      ▼
              ┌──────────────┐
              │  New Relic   │
              │   Cloud      │
              └──────────────┘
```

### Data Collection Flow

1. **Agent Initialization**
   - Reads configuration from `/etc/newrelic-infra/integrations.d/`
   - Establishes database connections
   - Validates permissions

2. **Metric Collection** (every 30-60s)
   - Queries database statistics
   - Collects performance metrics
   - Gathers query performance data

3. **Data Transmission**
   - Batches metrics
   - Compresses payload
   - Sends via HTTPS to New Relic

## Security Best Practices

### Credential Management
```yaml
# Multiple options for secure credential storage:
credentials:
  # Option 1: AWS Secrets Manager
  password_source: aws_secrets_manager
  password_key: /prod/database/password
  
  # Option 2: SSM Parameter Store
  password_source: aws_ssm_parameter
  password_key: /prod/database/password
  
  # Option 3: Local encrypted file
  password_source: file
  password_file: /secure/passwords/db.enc
```

### Network Security
- **Least privilege security groups** - Only required ports
- **Private subnet deployment** - No public IP needed
- **Encrypted transmission** - All data sent via HTTPS
- **IAM instance profiles** - No hardcoded AWS credentials

## Scaling Patterns

### Small Scale (1-50 databases)
- Single t3.medium instance
- All databases in one config
- Simple and cost-effective

### Medium Scale (50-200 databases)
- Single t3.large instance
- Grouped by environment
- Increased collection intervals

### Large Scale (200+ databases)
- Multiple monitoring instances
- Split by region/type/criticality
- Centralized configuration management

## Cost Optimization

### Development Costs
- **LocalStack testing**: $0
- **Local Docker resources**: Minimal
- **CI/CD pipeline testing**: $0

### Production Costs (Monthly)
- **t3.medium EC2**: ~$30
- **30GB EBS storage**: ~$3
- **Data transfer**: ~$5
- **Total**: ~$38/month for up to 100 databases

## Troubleshooting & Support

### Built-in Diagnostics
```bash
# Verify setup before deployment
./scripts/setup-verification.sh

# Test database connections
./scripts/test-db-connection.sh

# Validate query monitoring
./scripts/validate-query-monitoring.sh
```

### Common Issues Resolution
- **Pre-flight checks** catch configuration errors
- **Detailed logging** for debugging
- **Health checks** ensure continuous operation
- **Automated recovery** from transient failures

## Why This Approach?

1. **Faster Time to Value**
   - From zero to monitoring in under 15 minutes
   - No manual configuration required

2. **Reduced Risk**
   - Test everything locally first
   - Automated rollback capabilities
   - No production surprises

3. **Lower Operational Overhead**
   - Self-documenting infrastructure
   - Repeatable deployments
   - Easy updates and maintenance

4. **Better Developer Experience**
   - Focus on your databases, not infrastructure
   - Clear documentation and examples
   - Active community support

## Next Steps

1. **Get Started**: Follow our [Quick Start Guide](../QUICK_START.md)
2. **Customize**: See [Configuration Guide](CONFIGURATION.md)
3. **Scale Up**: Check [Best Practices](BEST_PRACTICES.md)
4. **Get Help**: Visit [Troubleshooting](TROUBLESHOOTING.md)

---

*Built with ❤️ by the New Relic team to make database monitoring accessible to everyone.*