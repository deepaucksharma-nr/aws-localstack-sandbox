# Testing

We use LocalStack Community Edition (free) to test without burning AWS credits. All AWS services used in our tests are fully supported by the free Community tier.

## Quick Start

```bash
# Start everything
make start

# Run tests
make test

# Clean up
make stop
```

## LocalStack Compatibility

This project is fully compatible with LocalStack Community Edition (free tier). We only use services available in the Community edition:
- EC2 (instances, security groups)
- IAM (roles, policies)
- SSM Parameter Store
- Secrets Manager
- VPC networking

## What's Running

When you run `make start`:
- LocalStack Community Edition (fake AWS) on port 4566
- MySQL on port 3306 (user: newrelic, pass: newrelic123)
- PostgreSQL on port 5432 (user: newrelic, pass: newrelic123)
- Mock New Relic API on port 8080

## Running Tests

```bash
# All tests
make test

# Just unit tests (no containers needed)
make test-unit

# Integration tests only
make test-integration

# End-to-end deployment test
make test-e2e
```

## Writing Tests

### Unit test example
```python
# test/unit/test_config.py
def test_database_config_valid():
    config = load_config('databases.yml')
    assert 'mysql_databases' in config
    assert len(config['mysql_databases']) > 0
```

### Integration test example
```python
# test/integration/test_mysql.py
def test_mysql_connection():
    conn = mysql.connect(host='mysql-test', user='newrelic')
    assert conn.is_connected()
```

## Debugging

```bash
# See what's happening
docker-compose logs -f

# Jump into test container
docker-compose exec test-runner bash

# Check if services are up
docker-compose ps
```

## Common Issues

**Port already in use?**
```bash
# Kill whatever's using the ports
lsof -ti:3306 | xargs kill -9
lsof -ti:5432 | xargs kill -9
```

**Tests failing randomly?**
```bash
# Clean start
make clean
make start
make test
```

**Need to test manually?**
```bash
# Deploy to LocalStack
cd terraform
terraform init
terraform apply -var-file=terraform.localstack.tfvars

# Check fake AWS
aws --endpoint-url=http://localhost:4566 ec2 describe-instances
```

## CI/CD

Tests run automatically on PRs. See `.github/workflows/ci.yml`.

To run CI locally:
```bash
act -j test-unit
```