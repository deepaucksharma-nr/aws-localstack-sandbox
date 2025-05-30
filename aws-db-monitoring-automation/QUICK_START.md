# Quick Start Guide

Get up and running with New Relic database monitoring in under 10 minutes!

## Prerequisites Checklist

- [ ] AWS Account with appropriate permissions
- [ ] New Relic account with Infrastructure Pro license
- [ ] Existing VPC and subnet IDs
- [ ] SSH key pair created in AWS
- [ ] Database credentials (read-only user)

## 5-Minute Setup

### 1. Clone the Repository

```bash
git clone https://github.com/newrelic/aws-db-monitoring-automation.git
cd aws-db-monitoring-automation
```

### 2. Configure Your Environment

```bash
# Copy example configurations
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp config/databases.example.yml config/databases.yml

# Edit with your values
nano terraform/terraform.tfvars
```

**Required values in terraform.tfvars:**
```hcl
aws_region              = "us-east-1"
vpc_id                 = "vpc-xxxxx"      # Your VPC ID
subnet_id              = "subnet-xxxxx"   # Your private subnet ID
key_name               = "my-ssh-key"     # Your AWS SSH key name
newrelic_license_key   = "xxxxx"         # Your New Relic license key
newrelic_account_id    = "xxxxx"         # Your New Relic account ID
```

### 3. Configure Your Databases

Edit `config/databases.yml`:

```yaml
newrelic_license_key: "YOUR_LICENSE_KEY_HERE"
newrelic_account_id: "YOUR_ACCOUNT_ID_HERE"

mysql_databases:
  - host: mysql.example.com
    port: 3306
    user: newrelic
    password: "your_password"
    service_name: production-mysql

postgresql_databases:
  - host: postgres.example.com
    port: 5432
    user: newrelic
    password: "your_password"
    database: postgres
    service_name: production-postgres
```

### 4. Deploy!

```bash
./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem
```

### 5. Verify in New Relic

1. Go to [New Relic One](https://one.newrelic.com)
2. Navigate to Infrastructure → Databases
3. You should see your databases within 2-3 minutes

## Quick Test with LocalStack

Want to test without AWS resources? Use our LocalStack setup:

```bash
# Start test environment
make start

# Run deployment against LocalStack
make deploy-local

# Run tests
make test

# Clean up
make stop
```

## Common Quick Fixes

### "Cannot connect to database"
```bash
# Test from monitoring instance
ssh -i ~/.ssh/your-key.pem ec2-user@<instance-ip>
mysql -h your-database.com -u newrelic -p
```

### "No data in New Relic"
```bash
# Check agent status on monitoring instance
sudo systemctl status newrelic-infra
sudo journalctl -u newrelic-infra -n 50
```

### "Permission denied"
```sql
-- MySQL: Grant required permissions
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'newrelic'@'%';

-- PostgreSQL: Grant monitor role
GRANT pg_monitor TO newrelic;
```

## Next Steps

- 📖 Read the [Architecture Overview](docs/ARCHITECTURE.md)
- 🔒 Review [Security Best Practices](docs/BEST_PRACTICES.md#security-best-practices)
- 📊 Set up [Custom Dashboards](docs/DASHBOARDS.md)
- 🚨 Configure [Alerts](docs/ALERTING.md)

## Need Help?

- 💬 [Community Forum](https://discuss.newrelic.com)
- 📚 [Documentation](https://docs.newrelic.com)
- 🎫 [Support](https://support.newrelic.com)

---

**Pro Tip**: Start with one database in development, validate everything works, then scale to production!