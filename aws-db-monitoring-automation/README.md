# AWS New Relic Database Monitoring Automation

This automation setup creates AWS EC2 instances, installs New Relic Infrastructure agent, and configures database monitoring (On Host Integration - OHI) for MySQL and PostgreSQL databases.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Ansible >= 2.9
- An existing VPC and subnet in AWS
- SSH key pair created in AWS
- New Relic account with:
  - Valid license key
  - Account ID

## Directory Structure

```
aws-db-monitoring-automation/
├── terraform/                 # Terraform configuration for AWS resources
│   ├── main.tf               # Main Terraform configuration
│   ├── variables.tf          # Variable definitions
│   ├── outputs.tf            # Output definitions
│   └── terraform.tfvars.example
├── ansible/                   # Ansible automation
│   ├── playbooks/            # Ansible playbooks
│   │   └── install-newrelic.yml
│   ├── templates/            # Configuration templates
│   │   ├── newrelic-infra.yml.j2
│   │   ├── mysql-config.yml.j2
│   │   └── postgresql-config.yml.j2
│   └── inventory/            # Ansible inventory files
│       └── hosts.yml.example
├── scripts/                   # Automation scripts
│   └── deploy-monitoring.sh  # Main deployment script
└── config/                    # Configuration files
    └── databases.example.yml # Example database configuration
```

## Quick Start

1. **Clone and prepare configuration:**
   ```bash
   cd aws-db-monitoring-automation
   
   # Copy and edit Terraform variables
   cp terraform/terraform.tfvars.example terraform/terraform.tfvars
   
   # Copy and edit database configuration
   cp config/databases.example.yml config/databases.yml
   ```

2. **Edit configuration files:**
   - `terraform/terraform.tfvars`: Set your AWS region, VPC ID, subnet ID, SSH key name, and New Relic credentials
   - `config/databases.yml`: Add your New Relic license key and MySQL/PostgreSQL database details

3. **Run the deployment:**
   ```bash
   ./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem
   ```

## Configuration

### Terraform Variables (terraform.tfvars)

```hcl
aws_region              = "us-east-1"
instance_type           = "t3.medium"
key_name               = "your-ssh-key-name"
vpc_id                 = "vpc-xxxxxxxxx"
subnet_id              = "subnet-xxxxxxxxx"
monitoring_server_name = "db-monitoring-server"
allowed_ssh_cidr_blocks = ["10.0.0.0/8"]
newrelic_license_key   = "your-newrelic-license-key"
newrelic_account_id    = "your-newrelic-account-id"
newrelic_region        = "US"  # or "EU"
```

### Database Configuration (databases.yml)

The database configuration file supports the following parameters:

**MySQL Integration:**
- `host`: Database hostname or IP
- `port`: Database port (default: 3306)
- `user`: Monitoring user username
- `password`: Monitoring user password
- `service_name`: Custom name for the service in New Relic
- `extended_metrics`: Enable extended metrics collection (true/false)
- `custom_labels`: Additional labels for categorization
- `tls_enabled`: Enable TLS connection (true/false)
- `interval`: Metrics collection interval (default: 30s)

**PostgreSQL Integration:**
- `host`: Database hostname or IP
- `port`: Database port (default: 5432)
- `user`: Monitoring user username
- `password`: Monitoring user password
- `database`: Database name to connect to
- `service_name`: Custom name for the service in New Relic
- `sslmode`: SSL mode (disable, require, verify-ca, verify-full)
- `collect_bloat_metrics`: Collect table bloat metrics (true/false)
- `collect_db_lock_metrics`: Collect database lock metrics (true/false)
- `custom_labels`: Additional labels for categorization
- `interval`: Metrics collection interval (default: 30s)

### Deployment Script Options

```bash
./scripts/deploy-monitoring.sh [OPTIONS]

OPTIONS:
    -k, --ssh-key PATH          Path to SSH private key for instance access
    -c, --config PATH           Path to database configuration file
    -i, --inventory PATH        Path to Ansible inventory file
    --skip-terraform            Skip Terraform deployment (use existing instance)
    --skip-ansible              Skip Ansible configuration
    -h, --help                  Display help message
```

## Usage Examples

### Full Deployment
```bash
./scripts/deploy-monitoring.sh -k ~/.ssh/production-key.pem
```

### Using Existing Infrastructure
```bash
# Create inventory file manually
cat > ansible/inventory/hosts.yml << EOF
all:
  hosts:
    monitoring_server:
      ansible_host: 10.0.1.100
      ansible_user: ec2-user
      ansible_ssh_private_key_file: ~/.ssh/production-key.pem
EOF

# Run only Ansible configuration
./scripts/deploy-monitoring.sh \
  -k ~/.ssh/production-key.pem \
  --skip-terraform
```

### Manual Database Integration Setup
After deployment, you can manually add or modify database integrations:

```bash
# SSH into the monitoring server
ssh -i ~/.ssh/your-key.pem ec2-user@<instance-ip>

# Edit MySQL configuration
sudo vi /etc/newrelic-infra/integrations.d/mysql-config.yml

# Edit PostgreSQL configuration
sudo vi /etc/newrelic-infra/integrations.d/postgresql-config.yml

# Restart New Relic agent
sudo systemctl restart newrelic-infra
```

## Security Considerations

1. **Database Credentials**: 
   - Store sensitive passwords in Ansible Vault: `ansible-vault encrypt config/databases.yml`
   - Or use AWS Secrets Manager/Parameter Store
   
2. **Network Security**: 
   - Ensure security groups allow database connections from monitoring server
   - Use TLS/SSL for all database connections when possible
   
3. **New Relic License Key**: 
   - Keep your license key secure
   - Never commit it to version control

## Database User Permissions

### MySQL
For basic monitoring:
```sql
CREATE USER 'newrelic'@'%' IDENTIFIED BY 'secure_password';
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'newrelic'@'%';
```

For query performance monitoring (recommended):
```sql
-- Grant additional permissions for performance schema
GRANT SELECT ON performance_schema.* TO 'newrelic'@'%';
GRANT SELECT ON information_schema.* TO 'newrelic'@'%';

-- Run the setup script for full configuration
mysql < scripts/setup-mysql-monitoring.sql
```

### PostgreSQL
For basic monitoring:
```sql
CREATE USER newrelic WITH PASSWORD 'secure_password';
GRANT SELECT ON pg_stat_database TO newrelic;
GRANT SELECT ON pg_stat_database_conflicts TO newrelic;
GRANT SELECT ON pg_stat_bgwriter TO newrelic;
```

For query performance monitoring (recommended):
```sql
-- Enable pg_stat_statements extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Grant query monitoring permissions
GRANT pg_read_all_stats TO newrelic;

-- Run the setup script for full configuration
psql -f scripts/setup-postgresql-monitoring.sql
```

## Monitoring in New Relic

Once deployed, you can view your database metrics in New Relic:

1. **Infrastructure**: https://one.newrelic.com/infrastructure
2. **Databases**: https://one.newrelic.com/infrastructure/databases
3. **Query Performance**: Available in the database entity views

### Query Performance Monitoring Features

With query performance monitoring enabled, you'll have access to:

#### PostgreSQL
- **Top Slow Queries**: Identify queries consuming the most time
- **Query Wait Events**: Understand what queries are waiting for
- **Long Running Queries**: Track queries exceeding time thresholds
- **Table Bloat Analysis**: Monitor table and index bloat
- **Index Usage Statistics**: Find unused or rarely used indexes

#### MySQL
- **Query Digest Analysis**: See normalized queries with execution statistics
- **Wait Event Monitoring**: Track current wait events across connections
- **Long Running Query Detection**: Identify stuck or slow queries
- **Table Statistics**: Monitor table sizes and fragmentation
- **Lock Wait Analysis**: Understand lock contention issues

### Configuring Query Monitoring

Query monitoring is enabled by default when you use this automation. To customize:

```yaml
# In your databases.yml configuration
mysql_databases:
  - host: your-mysql-host
    # ... other settings ...
    enable_query_monitoring: true      # Enable/disable query monitoring
    query_metrics_interval: 60s        # How often to collect query metrics
    max_sql_query_length: 1000         # Maximum query text length to capture
    gather_query_samples: true         # Collect actual query samples

postgresql_databases:
  - host: your-postgres-host
    # ... other settings ...
    enable_query_monitoring: true      # Enable/disable query monitoring
    query_metrics_interval: 60s        # How often to collect query metrics
    max_sql_query_length: 1000         # Maximum query text length to capture
    # custom_metrics_query_file: /path/to/custom-queries.yml  # Optional: custom queries
```

## Troubleshooting

1. **Agent Connection Issues**:
   ```bash
   # Check agent status
   sudo systemctl status newrelic-infra
   
   # View agent logs
   sudo journalctl -u newrelic-infra -f
   
   # Test connectivity to New Relic
   curl -I https://infrastructure-api.newrelic.com/
   ```

2. **Database Connection Issues**:
   ```bash
   # Check integration configuration
   sudo cat /etc/newrelic-infra/integrations.d/mysql-config.yml
   sudo cat /etc/newrelic-infra/integrations.d/postgresql-config.yml
   
   # Test database connectivity
   mysql -h <host> -u <user> -p
   psql -h <host> -U <user> -d <database>
   ```

3. **Missing Metrics**:
   - Verify database user permissions
   - Check security groups allow connections
   - Ensure integration interval is appropriate
   - Review agent logs for errors

4. **Query Performance Metrics Not Showing**:
   
   **PostgreSQL:**
   - Verify pg_stat_statements extension is enabled: `SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';`
   - Check user has pg_read_all_stats role: `SELECT rolname FROM pg_roles WHERE pg_has_role('newrelic', oid, 'member');`
   - Ensure postgresql.conf has: `shared_preload_libraries = 'pg_stat_statements'`
   - Restart PostgreSQL after configuration changes
   
   **MySQL:**
   - Verify performance_schema is enabled: `SHOW VARIABLES LIKE 'performance_schema';`
   - Check statement consumers: `SELECT * FROM performance_schema.setup_consumers WHERE NAME LIKE '%statement%';`
   - Ensure user has performance_schema access: `SHOW GRANTS FOR 'newrelic'@'%';`
   - MySQL 8.0+ required for full query monitoring support

## Clean Up

To remove all created resources:

```bash
cd terraform/
terraform destroy
```

## Testing with LocalStack

This project includes a comprehensive testing setup using LocalStack to simulate AWS services locally.

### Quick Start Testing

```bash
# Start test environment
make start

# Run all tests
make test

# Run specific test suites
make test-unit
make test-integration
make test-e2e

# Stop test environment
make stop
```

### Test Environment Components

1. **LocalStack**: Simulates AWS services (EC2, VPC, Security Groups)
2. **MySQL Container**: Test MySQL database with sample data
3. **PostgreSQL Container**: Test PostgreSQL database with sample data
4. **Mock New Relic API**: Simulates New Relic endpoints for testing
5. **Test Runner**: Container with all testing tools pre-installed

### Running Tests Manually

```bash
# Start all services
docker-compose up -d

# Run tests inside the test container
docker-compose exec test-runner /usr/local/bin/run-tests.sh all

# View logs
docker-compose logs -f

# Clean up
docker-compose down -v
```

### Test Configuration

For testing, use the LocalStack configuration:
```bash
cd terraform
terraform init
terraform plan -var-file=terraform.localstack.tfvars
terraform apply -var-file=terraform.localstack.tfvars
```

### CI/CD Pipeline

The project includes GitHub Actions workflows for:
- Linting and validation
- Unit tests
- Integration tests
- End-to-end tests
- Security scanning
- Automated releases

### Development Workflow

1. Make changes to code
2. Run tests locally: `make test`
3. Fix any issues
4. Commit and push
5. CI/CD pipeline runs automatically

## Support

For New Relic specific issues:
- Documentation: https://docs.newrelic.com/docs/infrastructure/
- Support: https://support.newrelic.com/