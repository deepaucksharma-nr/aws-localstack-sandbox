# AWS Database Monitoring with New Relic

Terraform + Ansible automation to deploy New Relic monitoring for MySQL and PostgreSQL databases on AWS.

## What this does

- Spins up an EC2 instance 
- Installs New Relic Infrastructure agent
- Configures database monitoring for MySQL/PostgreSQL
- Enables query performance tracking

## Quick Start

```bash
# Clone it
git clone https://github.com/newrelic/aws-db-monitoring-automation.git
cd aws-db-monitoring-automation

# Set up your configs
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp config/databases.example.yml config/databases.yml

# Edit them (add your AWS stuff, New Relic license key, database info)
vim terraform/terraform.tfvars
vim config/databases.yml

# Deploy
./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem
```

Done. Check New Relic in ~5 minutes.

## Prerequisites

- AWS account
- New Relic license key
- VPC and subnet already set up
- SSH key pair in AWS
- Database user with monitoring permissions

## What's in here

```
terraform/          # AWS infrastructure
ansible/            # New Relic agent setup  
config/             # Database configs
scripts/            # Deployment scripts
test/               # LocalStack tests
```

## Database Setup

### MySQL
```sql
CREATE USER 'newrelic'@'%' IDENTIFIED BY 'password';
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'newrelic'@'%';
GRANT SELECT ON performance_schema.* TO 'newrelic'@'%';
```

### PostgreSQL
```sql
CREATE USER newrelic WITH PASSWORD 'password';
GRANT pg_monitor TO newrelic;
```

## Testing Locally

We use LocalStack Community Edition (free) so you don't burn AWS credits:

```bash
make start  # Start local environment
make test   # Run tests
make stop   # Clean up
```

**Note:** This project is fully compatible with LocalStack Community Edition. No paid features required.

## Common Issues

**No data showing up?**
- Check agent: `sudo systemctl status newrelic-infra`
- Check logs: `sudo journalctl -u newrelic-infra -n 100`

**Can't connect to database?**
- Security groups - make sure port 3306/5432 is open from monitoring instance
- Test connection: `nc -zv your-database.com 3306`

**Query monitoring not working?**
- MySQL: Performance Schema must be ON
- PostgreSQL: pg_stat_statements extension must be installed

## Configuration

### terraform.tfvars
```hcl
aws_region = "us-east-1"
vpc_id     = "vpc-xxxxx"
subnet_id  = "subnet-xxxxx"
key_name   = "your-ssh-key"
newrelic_license_key = "YOUR_LICENSE_KEY"
```

### databases.yml
```yaml
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

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - How it works
- [Configuration Guide](docs/CONFIGURATION.md) - All configuration options
- [Best Practices](docs/BEST_PRACTICES.md) - Security and scaling patterns
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and fixes

## Contributing

PRs welcome. Run tests before submitting.

## License

Apache 2.0