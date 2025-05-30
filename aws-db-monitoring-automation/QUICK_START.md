# Quick Start

## Before you start

You need:
- AWS account 
- New Relic license key
- Terraform and Ansible installed
- A VPC with a subnet
- SSH key in AWS

## 1. Clone and configure

```bash
git clone https://github.com/newrelic/aws-db-monitoring-automation.git
cd aws-db-monitoring-automation

# Copy configs
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp config/databases.example.yml config/databases.yml
```

## 2. Update terraform.tfvars

```hcl
aws_region           = "us-east-1"
vpc_id              = "vpc-12345"
subnet_id           = "subnet-12345"
key_name            = "my-key"
newrelic_license_key = "YOUR_LICENSE_KEY"
newrelic_account_id = "123456"
```

## 3. Update databases.yml

```yaml
newrelic_license_key: "YOUR_LICENSE_KEY"

mysql_databases:
  - host: mysql.example.com
    user: newrelic
    password: password

postgresql_databases:
  - host: postgres.example.com
    user: newrelic  
    password: password
    database: postgres
```

## 4. Set up database users

MySQL:
```bash
mysql -u root -p < scripts/setup-mysql-monitoring.sql
```

PostgreSQL:
```bash
psql -U postgres -f scripts/setup-postgresql-monitoring.sql
```

## 5. Deploy

```bash
./scripts/deploy-monitoring.sh -k ~/.ssh/my-key.pem
```

## 6. Check New Relic

Go to https://one.newrelic.com/infrastructure - your stuff should show up in a few minutes.

## Verification Scripts

We have several scripts to help verify your setup:

```bash
# Test database connections before deployment
./scripts/test-db-connection.sh \
  --mysql-host mysql.example.com \
  --mysql-pass password

# Verify the complete setup after deployment
./scripts/setup-verification.sh --verbose

# Validate query monitoring is working
./scripts/validate-query-monitoring.sh \
  --mysql-host mysql.example.com \
  --mysql-pass password
```

## Troubleshooting

Not working? Check:

1. Agent running: `ssh to instance` then `sudo systemctl status newrelic-infra`
2. Can reach database: `nc -zv your-database 3306`
3. Logs: `sudo journalctl -u newrelic-infra -f`

## Test first?

```bash
# Use LocalStack to test without AWS charges
make start
make test
```