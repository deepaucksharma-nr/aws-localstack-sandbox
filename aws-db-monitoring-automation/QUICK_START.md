# Quick Start Guide

Get New Relic database monitoring deployed in under 10 minutes! This guide walks you through the fastest path to monitoring your MySQL and PostgreSQL databases.

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] AWS Account with appropriate IAM permissions
- [ ] New Relic account with Infrastructure Pro license
- [ ] AWS CLI installed and configured
- [ ] Terraform >= 1.0 installed
- [ ] Ansible >= 2.9 installed
- [ ] An existing VPC and subnet in AWS
- [ ] SSH key pair created in your AWS region

## Step 1: Clone and Setup (2 minutes)

```bash
# Clone the repository
git clone https://github.com/newrelic/aws-db-monitoring-automation.git
cd aws-db-monitoring-automation

# Run setup verification
./scripts/setup-verification.sh --step-by-step
```

## Step 2: Configure AWS Resources (3 minutes)

```bash
# Copy and edit Terraform configuration
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars`:
```hcl
aws_region              = "us-east-1"              # Your AWS region
instance_type           = "t3.medium"              # Monitoring instance size
key_name               = "my-aws-key"              # Your AWS SSH key name
vpc_id                 = "vpc-12345678"            # Your VPC ID
subnet_id              = "subnet-12345678"         # Your subnet ID
monitoring_server_name = "nr-db-monitor"           # Instance name
allowed_ssh_cidr_blocks = ["10.0.0.0/8"]          # Your IP range for SSH
newrelic_license_key   = "YOUR_LICENSE_KEY_HERE"  # Your New Relic license
newrelic_account_id    = "1234567"                # Your New Relic account ID
newrelic_region        = "US"                      # US or EU
```

## Step 3: Configure Databases (2 minutes)

```bash
# Copy and edit database configuration
cp config/databases.example.yml config/databases.yml
```

Edit `config/databases.yml` with your database details:
```yaml
newrelic_license_key: "YOUR_LICENSE_KEY_HERE"
newrelic_account_id: "1234567"

mysql_databases:
  - host: mysql.example.com
    port: 3306
    user: newrelic
    password: "secure_password"
    enable_query_monitoring: true    # Enable query performance insights

postgresql_databases:
  - host: postgres.example.com
    port: 5432
    user: newrelic
    password: "secure_password"
    database: postgres
    enable_query_monitoring: true    # Enable pg_stat_statements monitoring
```

## Step 4: Prepare Your Databases (3 minutes)

### For MySQL:
```sql
-- Run on your MySQL server
CREATE USER 'newrelic'@'%' IDENTIFIED BY 'secure_password';
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'newrelic'@'%';
GRANT SELECT ON performance_schema.* TO 'newrelic'@'%';
```

Or use our script:
```bash
mysql -u root -p < scripts/setup-mysql-monitoring.sql
```

### For PostgreSQL:
```sql
-- Run on your PostgreSQL server
CREATE USER newrelic WITH PASSWORD 'secure_password';
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT pg_read_all_stats TO newrelic;
```

Or use our script:
```bash
psql -U postgres -f scripts/setup-postgresql-monitoring.sql
```

## Step 5: Test Database Connections (Optional)

```bash
# Test connections before deployment
./scripts/test-db-connection.sh \
  --mysql-host mysql.example.com \
  --mysql-pass your_password \
  --pg-host postgres.example.com \
  --pg-pass your_password
```

## Step 6: Deploy! (2 minutes)

```bash
# Run the deployment
./scripts/deploy-monitoring.sh -k ~/.ssh/my-aws-key.pem

# The script will:
# 1. Run pre-flight checks
# 2. Create AWS infrastructure with Terraform
# 3. Install New Relic agent with Ansible
# 4. Configure database monitoring
```

## Step 7: Verify in New Relic

After deployment completes:

1. **Infrastructure**: https://one.newrelic.com/infrastructure
   - You should see your monitoring instance within 1-2 minutes

2. **Databases**: https://one.newrelic.com/infrastructure/databases
   - Database entities appear within 3-5 minutes

3. **Query Performance**: Click on any database to see query insights
   - Query data populates after 5-10 minutes of activity

## Common Quick Fixes

### "terraform.tfvars contains placeholder values"
```bash
# Ensure all YOUR_* placeholders are replaced with actual values
grep "YOUR_" terraform/terraform.tfvars
```

### "Cannot connect to database"
```bash
# Check security groups allow monitoring instance access
# MySQL: port 3306, PostgreSQL: port 5432
aws ec2 describe-security-groups --group-ids sg-xxxxx
```

### "No query data showing"
```bash
# Validate query monitoring setup
./scripts/validate-query-monitoring.sh \
  --mysql-host your-host --mysql-pass your-pass
```

## What's Next?

- **Custom Dashboards**: Import our dashboard templates
- **Alerts**: Set up proactive alerting
- **Advanced Config**: See [Configuration Guide](docs/CONFIGURATION.md)
- **Troubleshooting**: See [Troubleshooting Guide](docs/TROUBLESHOOTING.md)

## Need Help?

- Run setup verification: `./scripts/setup-verification.sh --verbose`
- Check logs: `sudo journalctl -u newrelic-infra -f`
- Community: https://discuss.newrelic.com
- Support: https://support.newrelic.com