# Configuration Guide

## Basic Setup

### terraform.tfvars
```hcl
# Required
aws_region           = "us-east-1"
vpc_id              = "vpc-12345"
subnet_id           = "subnet-12345" 
key_name            = "my-ssh-key"
newrelic_license_key = "YOUR_LICENSE_KEY"
newrelic_account_id = "123456"

# Optional
instance_type = "t3.medium"
monitoring_server_name = "db-monitor"
```

### databases.yml
```yaml
# Minimal config
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

## Advanced Options

### MySQL Configuration
```yaml
mysql_databases:
  - host: mysql-prod.example.com
    port: 3306
    user: newrelic
    password: password
    
    # Query monitoring
    enable_query_monitoring: true
    query_metrics_interval: 60s
    max_sql_query_length: 1000
    
    # Extended metrics
    extended_metrics: true
    interval: 30s
    
    # TLS
    tls_enabled: true
    tls_ca: /path/to/ca.pem
    
    # Labels
    custom_labels:
      environment: production
      team: backend
      region: us-east-1
```

### PostgreSQL Configuration
```yaml
postgresql_databases:
  - host: postgres-prod.example.com
    port: 5432
    user: newrelic
    password: password
    database: postgres
    
    # Query monitoring
    enable_query_monitoring: true
    query_metrics_interval: 60s
    
    # SSL
    sslmode: require  # disable, allow, prefer, require, verify-ca, verify-full
    ssl_root_cert_location: /path/to/root.crt
    
    # Collection options
    collect_bloat_metrics: true
    collect_db_lock_metrics: true
    collection_list: "ALL"  # or specific databases
    
    # Labels
    custom_labels:
      environment: production
      application: api
```

## Environment Variables

You can use environment variables instead of hardcoding:

```yaml
mysql_databases:
  - host: ${MYSQL_HOST}
    user: ${MYSQL_USER}
    password: ${MYSQL_PASSWORD}
```

Then:
```bash
export MYSQL_HOST=mysql.example.com
export MYSQL_USER=newrelic
export MYSQL_PASSWORD=supersecret
```

## Multiple Environments

### Option 1: Separate config files
```bash
config/
├── databases-prod.yml
├── databases-staging.yml
└── databases-dev.yml
```

Deploy with:
```bash
./scripts/deploy-monitoring.sh -c config/databases-prod.yml
```

### Option 2: Single file with all environments
```yaml
# databases.yml
mysql_databases:
  # Production
  - host: mysql-prod.example.com
    user: newrelic
    password: ${PROD_MYSQL_PASSWORD}
    custom_labels:
      environment: production
      
  # Staging
  - host: mysql-staging.example.com
    user: newrelic
    password: ${STAGING_MYSQL_PASSWORD}
    custom_labels:
      environment: staging
```

## Custom Metrics

Add your own SQL queries:

```yaml
# custom-queries.yml
queries:
  - name: user_count
    query: SELECT COUNT(*) as value FROM users
    interval: 300s
    
  - name: order_backlog
    query: |
      SELECT COUNT(*) as value 
      FROM orders 
      WHERE status = 'pending' 
      AND created_at < NOW() - INTERVAL 1 HOUR
    interval: 60s
```

## Secrets Management

### Using AWS Secrets Manager
```yaml
mysql_databases:
  - host: mysql.example.com
    user: newrelic
    password_from_secret: "arn:aws:secretsmanager:us-east-1:123456789:secret:db-password"
```

### Using AWS Parameter Store
```yaml
postgresql_databases:
  - host: postgres.example.com
    user: newrelic
    password_from_parameter: "/myapp/db/password"
```

## Validation

Check your config:
```bash
# Validate YAML syntax
yamllint config/databases.yml

# Test database connections
./scripts/test-db-connection.sh \
  --config config/databases.yml \
  --validate-only
```