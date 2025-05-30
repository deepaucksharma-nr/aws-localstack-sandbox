# AWS Database Monitoring Automation

A comprehensive infrastructure-as-code solution for automated database monitoring using New Relic on AWS. This project provides secure, scalable deployment of monitoring infrastructure for MySQL and PostgreSQL databases across various AWS services.

## 🚀 Features

- **Multi-Database Support**: Monitor MySQL and PostgreSQL databases
- **Multi-Provider Support**: Works with RDS, Aurora, EC2-hosted, and containerized databases
- **Secure by Default**: Implements security best practices including:
  - Restricted IAM policies with least privilege
  - Encrypted secrets management via AWS Secrets Manager and SSM
  - SSL/TLS enforcement for database connections
  - Secure Docker configurations with non-root users
- **LocalStack Compatible**: Full support for local development and testing
- **Automated Deployment**: One-command deployment with comprehensive error handling
- **Lifecycle Management**: Built-in backup, restore, and cleanup capabilities

## 📋 Prerequisites

- Docker and Docker Compose
- Terraform >= 1.0
- AWS CLI v2
- Python 3.8+
- Ansible 2.9+
- jq

## 🏃 Quick Start

### Local Development with LocalStack

```bash
# Generate secure secrets
./scripts/generate-secrets.sh

# Start LocalStack and databases
docker-compose up -d

# Run the quick start script
./quickstart.sh

# Or use the comprehensive demo
./scripts/localstack-e2e-demo.sh
```

### Production Deployment

```bash
# Configure your AWS credentials
aws configure

# Create terraform.tfvars from example
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy infrastructure
./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem

# For auto-approved deployment
./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem --auto-approve
```

## 🔧 Configuration

### Database Configuration

Create `config/databases.yml` from the example:

```bash
cp config/databases.example.yml config/databases.yml
```

Example configuration:

```yaml
mysql_databases:
  - name: production-mysql
    type: mysql
    enabled: true
    provider: rds
    connection:
      host: mysql.example.com
      port: 3306
    credentials:
      user_source: plain
      user: newrelic
      password_source: aws_secrets_manager
      password_key: /prod/mysql/password
    monitoring:
      interval: 30s
      extended_metrics: true

postgresql_databases:
  - name: production-postgres
    type: postgresql
    enabled: true
    provider: rds
    connection:
      host: postgres.example.com
      port: 5432
      database: myapp
      ssl_mode: require
    credentials:
      user_source: plain
      user: newrelic
      password_source: aws_ssm_parameter
      password_key: /prod/postgres/password
```

### Terraform Variables

Key variables in `terraform/terraform.tfvars`:

```hcl
# Network Configuration
vpc_id    = "vpc-xxxxxx"
subnet_id = "subnet-xxxxxx"

# Access Control
allowed_ssh_cidr_blocks  = ["10.0.0.0/8"]  # Your IP range
allowed_http_cidr_blocks = ["10.0.0.0/8"]  # Monitoring UI access

# Security
enable_https = true
enable_http  = false  # Disable in production

# New Relic
newrelic_license_key = "YOUR_LICENSE_KEY"
newrelic_account_id  = "YOUR_ACCOUNT_ID"
```

## 🛡️ Security Features

### IAM Policies
- Least privilege access with resource-specific permissions
- Restricted to specific secret/parameter prefixes
- KMS access limited to service-specific operations

### Network Security
- Configurable CIDR blocks for SSH and HTTP/HTTPS access
- Security groups with minimal required ports
- SSL/TLS enforcement for all database connections

### Secrets Management
- Integration with AWS Secrets Manager and SSM Parameter Store
- No plaintext passwords in configuration files
- Secure file permissions (0600) for sensitive files

### Docker Security
- Non-root user execution
- Resource limits enforced
- Read-only root filesystems where possible
- Health checks for all services

## 🔨 Management Scripts

### Deployment
```bash
# Full deployment with error handling and retries
./scripts/deploy-monitoring.sh -k ~/.ssh/key.pem

# Dry run to preview changes
./scripts/deploy-monitoring.sh -k ~/.ssh/key.pem --dry-run
```

### Configuration Management
```bash
# Transform and validate configurations
python3 scripts/transform-config.py config/databases.yml config/ansible-inventory.yml

# Validate database credentials
python3 scripts/validate-credentials.py config/databases.yml
```

### Lifecycle Management
```bash
# Create backup
./scripts/lifecycle-manager.sh backup

# Restore from backup
./scripts/lifecycle-manager.sh restore --file backups/backup-20240101-120000.tar.gz

# Rotate old backups
./scripts/lifecycle-manager.sh rotate --retention 14

# Health check
./scripts/lifecycle-manager.sh health-check

# Show system status
./scripts/lifecycle-manager.sh status
```

### Cleanup
```bash
# Clean up all resources
./scripts/cleanup-resources.sh --all

# Clean up Terraform resources only
./scripts/cleanup-resources.sh --terraform

# Clean up local files only
./scripts/cleanup-resources.sh --local

# Dry run to see what would be cleaned
./scripts/cleanup-resources.sh --all --dry-run
```

## 📁 Project Structure

```
.
├── terraform/              # Terraform configurations
│   ├── main.tf            # Main infrastructure
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Output values
│   └── modules/           # Reusable modules
├── ansible/               # Ansible playbooks
│   ├── playbooks/         # Installation playbooks
│   └── templates/         # Configuration templates
├── scripts/               # Management scripts
│   ├── lib/              # Shared libraries
│   ├── deploy-monitoring.sh
│   ├── transform-config.py
│   ├── validate-credentials.py
│   ├── lifecycle-manager.sh
│   └── cleanup-resources.sh
├── config/                # Configuration files
├── test/                  # Test suites
├── localstack/           # LocalStack initialization
└── mock-services/        # Mock New Relic API
```

## 🧪 Testing

### Unit Tests
```bash
cd test
python -m pytest unit/
```

### Integration Tests
```bash
# Start test environment
docker-compose up -d

# Run integration tests
./test/run-tests.sh
```

### End-to-End Tests
```bash
# Run complete E2E test with LocalStack
./scripts/localstack-e2e-demo.sh
```

## 🔍 Troubleshooting

### Check Service Health
```bash
# View service status
docker-compose ps

# Check logs
docker-compose logs -f [service-name]

# Run health check
./scripts/lifecycle-manager.sh health-check
```

### Common Issues

1. **LocalStack not starting**: Ensure Docker has enough resources (at least 4GB RAM)
2. **Terraform state lock**: Run `terraform force-unlock <lock-id>` if needed
3. **SSH connection timeout**: Check security group rules and network connectivity
4. **Credential errors**: Validate AWS credentials and secret paths

## 📚 Documentation

- [Quick Start Guide](QUICK_START.md) - Get up and running quickly
- [Security Best Practices](docs/SECURITY.md) - Security implementation details
- [Module Documentation](terraform/modules/README.md) - Terraform module usage

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- New Relic for their comprehensive monitoring platform
- LocalStack for enabling local AWS development
- The Terraform and Ansible communities

---

**Note**: This project implements security best practices. Always review and adjust security settings based on your specific requirements and compliance needs.