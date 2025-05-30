# Testing Guide

This document provides a comprehensive guide to testing the AWS Database Monitoring Automation project.

## Overview

The testing infrastructure uses LocalStack to simulate AWS services and Docker containers to provide test databases and mock New Relic endpoints. This allows for complete end-to-end testing without incurring AWS costs or requiring real New Relic accounts.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   LocalStack    │     │  Mock New Relic  │     │  Test Databases │
│   (AWS APIs)    │     │  (API Endpoints) │     │  MySQL/Postgres │
└────────┬────────┘     └────────┬─────────┘     └────────┬────────┘
         │                       │                          │
         └───────────────────────┴──────────────────────────┘
                                 │
                        ┌────────┴────────┐
                        │  Test Runner    │
                        │  (Pytest, etc)  │
                        └─────────────────┘
```

## Components

### 1. LocalStack
- **Purpose**: Simulates AWS EC2, VPC, Security Groups, SSM, and IAM
- **Access**: http://localhost:4566
- **Configuration**: Automatically creates VPC and subnets on startup

### 2. Mock New Relic Service
- **Purpose**: Simulates New Relic Infrastructure API and agent endpoints
- **API Port**: 8080 (Management API)
- **Agent Port**: 8081 (Agent communication)
- **Features**:
  - Agent registration
  - Metrics ingestion
  - Configuration validation
  - Admin endpoints for verification

### 3. Test Databases

#### MySQL
- **Port**: 3306
- **Database**: testdb, app_db
- **User**: newrelic / newrelic123
- **Features**: Pre-loaded test data, monitoring permissions

#### PostgreSQL
- **Port**: 5432
- **Database**: testdb, app_db
- **User**: newrelic / newrelic123
- **Features**: Pre-loaded test data, monitoring permissions

### 4. Test Runner Container
- **Base**: Ubuntu 22.04
- **Tools**: Terraform, Ansible, AWS CLI, pytest
- **Purpose**: Isolated environment for running tests

## Test Types

### Unit Tests (`test/unit/`)
- Configuration validation
- Template rendering
- Script functionality
- No external dependencies

### Integration Tests (`test/integration/`)
- LocalStack AWS service integration
- Database connectivity
- Mock New Relic API interaction
- Service health checks

### End-to-End Tests
- Complete deployment workflow
- Terraform provisioning
- Ansible configuration
- Agent installation simulation

## Running Tests

### Using Make (Recommended)

```bash
# Run all tests
make test

# Run specific test types
make test-unit
make test-integration
make test-e2e

# Start/stop test environment
make start
make stop

# View logs
make logs
```

### Using Docker Compose

```bash
# Start services
docker-compose up -d

# Run tests
docker-compose exec test-runner /usr/local/bin/run-tests.sh all

# Run specific suite
docker-compose exec test-runner /usr/local/bin/run-tests.sh unit
docker-compose exec test-runner /usr/local/bin/run-tests.sh integration

# Stop services
docker-compose down -v
```

### Local Development

```bash
# Install test dependencies
pip install -r test/requirements.txt

# Run unit tests locally
cd test
pytest unit/ -v

# Run with coverage
pytest unit/ --cov=/workspace --cov-report=html
```

## Writing Tests

### Unit Test Example

```python
def test_mysql_config_structure():
    """Test MySQL configuration structure"""
    config = load_config("databases.example.yml")
    mysql_dbs = config.get("mysql_databases", [])
    
    for db in mysql_dbs:
        assert "host" in db
        assert "user" in db
        assert "password" in db
```

### Integration Test Example

```python
def test_mysql_connectivity():
    """Test MySQL is accessible"""
    conn = mysql.connector.connect(
        host='mysql-test',
        user='newrelic',
        password='newrelic123'
    )
    cursor = conn.cursor()
    cursor.execute("SELECT 1")
    assert cursor.fetchone()[0] == 1
```

## Mock New Relic API

### Endpoints

#### Management API (Port 8080)
- `GET /health` - Health check
- `GET /v2/accounts/:accountId` - Account info
- `GET /v2/metrics/database` - Database metrics
- `GET /admin/agents` - List registered agents
- `GET /admin/metrics` - View collected metrics

#### Agent API (Port 8081)
- `GET /health` - Health check
- `POST /identity/v1/connect` - Agent registration
- `POST /agent/v1/metrics` - Send metrics
- `POST /agent/v1/inventory` - Send inventory
- `POST /agent/v1/events` - Send events

### Testing Agent Registration

```bash
# Register an agent
curl -X POST http://localhost:8081/identity/v1/connect \
  -H "Content-Type: application/json" \
  -d '{"license_key": "test_license_key_123", "hostname": "test-host"}'

# Check registered agents
curl http://localhost:8080/admin/agents
```

## Troubleshooting

### Common Issues

1. **Services not starting**
   ```bash
   # Check logs
   docker-compose logs localstack
   docker-compose logs mysql-test
   
   # Restart services
   docker-compose restart
   ```

2. **Database connection failures**
   ```bash
   # Test MySQL connection
   mysql -h localhost -P 3306 -u newrelic -pnewrelic123 testdb
   
   # Test PostgreSQL connection
   PGPASSWORD=newrelic123 psql -h localhost -p 5432 -U newrelic testdb
   ```

3. **LocalStack issues**
   ```bash
   # Check LocalStack health
   curl http://localhost:4566/_localstack/health
   
   # View LocalStack logs
   docker-compose logs localstack
   ```

### Debug Mode

```bash
# Run with debug output
DEBUG=1 make test

# View detailed logs
docker-compose logs -f --tail=100
```

## CI/CD Integration

The project includes GitHub Actions workflows that automatically:

1. Run linting and validation
2. Execute unit tests
3. Run integration tests with services
4. Perform security scanning
5. Build and publish artifacts

### Running CI Locally

```bash
# Install act (GitHub Actions local runner)
brew install act

# Run CI workflow locally
act -j test-unit
act -j test-integration
```

## Best Practices

1. **Always clean up**: Use `make clean` or `docker-compose down -v`
2. **Check logs**: When tests fail, check service logs first
3. **Isolate tests**: Each test should be independent
4. **Use fixtures**: Leverage pytest fixtures for common setup
5. **Mock external calls**: Don't make real API calls in tests

## Adding New Tests

1. Create test file in appropriate directory (`unit/` or `integration/`)
2. Follow naming convention: `test_*.py`
3. Use descriptive test names
4. Add necessary fixtures
5. Update CI workflow if needed

## Performance Testing

For performance testing:

```bash
# Run with timing
pytest -v --durations=10

# Profile tests
python -m cProfile -o profile.stats test/run_tests.py
```

## Security Testing

```bash
# Run security scans
make security

# Manual security checks
trivy fs .
checkov -d terraform/
```