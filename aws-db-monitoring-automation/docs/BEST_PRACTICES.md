# Best Practices Guide

## Overview

This guide provides New Relic's recommended best practices for deploying and operating database monitoring in production environments. Following these guidelines will ensure optimal performance, security, and reliability.

## Table of Contents

1. [Planning and Design](#planning-and-design)
2. [Security Best Practices](#security-best-practices)
3. [Deployment Best Practices](#deployment-best-practices)
4. [Database Configuration](#database-configuration)
5. [Monitoring Configuration](#monitoring-configuration)
6. [Operational Excellence](#operational-excellence)
7. [Performance Optimization](#performance-optimization)
8. [Troubleshooting Patterns](#troubleshooting-patterns)

## Planning and Design

### 1. Capacity Planning

**Calculate Your Requirements:**
```yaml
Monitoring Capacity Calculator:
  Small Deployment (1-20 databases):
    - Instance Type: t3.small
    - Memory: 2GB
    - Storage: 20GB
    
  Medium Deployment (20-50 databases):
    - Instance Type: t3.medium
    - Memory: 4GB
    - Storage: 30GB
    
  Large Deployment (50-100 databases):
    - Instance Type: t3.large
    - Memory: 8GB
    - Storage: 50GB
    
  Extra Large (100+ databases):
    - Multiple instances
    - Load distribution
    - Regional deployment
```

### 2. Network Architecture

**Recommended Network Design:**
```
Best Practice Network Layout:
├── Monitoring Subnet (Private)
│   └── Monitoring EC2 Instances
├── Database Subnet (Private)
│   └── RDS/Self-managed Databases
├── NAT Gateway (Public Subnet)
│   └── Outbound Internet Access
└── VPC Endpoints
    └── AWS Service Access
```

### 3. High Availability Planning

- **Multi-AZ Deployment**: Deploy monitoring instances across availability zones
- **Auto-recovery**: Enable EC2 auto-recovery for instance failures
- **Configuration Backup**: Store configurations in S3 with versioning
- **State Management**: Use remote Terraform state with locking

## Security Best Practices

### 1. Credential Management

**DO:**
```yaml
Recommended Approaches:
  - Use AWS Secrets Manager for database credentials
  - Rotate credentials regularly (90 days)
  - Use IAM roles for AWS API access
  - Implement least-privilege access
  - Enable MFA for administrative access
```

**DON'T:**
```yaml
Avoid These Patterns:
  - Hardcode credentials in configuration files
  - Use root database accounts for monitoring
  - Share credentials across environments
  - Store credentials in version control
  - Use default passwords
```

### 2. Database User Permissions

**MySQL Minimum Permissions:**
```sql
-- Create dedicated monitoring user
CREATE USER 'newrelic'@'%' IDENTIFIED BY 'strong_password_here';

-- Grant minimum required permissions
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'newrelic'@'%';

-- For query monitoring
GRANT SELECT ON performance_schema.* TO 'newrelic'@'%';

-- Restrict to monitoring server IP if possible
CREATE USER 'newrelic'@'10.0.1.100' IDENTIFIED BY 'strong_password_here';
```

**PostgreSQL Minimum Permissions:**
```sql
-- Create dedicated monitoring user
CREATE USER newrelic WITH PASSWORD 'strong_password_here';

-- Grant monitoring role (PG 10+)
GRANT pg_monitor TO newrelic;

-- For older versions
GRANT SELECT ON pg_stat_database TO newrelic;
GRANT SELECT ON pg_stat_bgwriter TO newrelic;
GRANT SELECT ON pg_stat_user_tables TO newrelic;

-- For query monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT SELECT ON pg_stat_statements TO newrelic;
```

### 3. Network Security

**Security Group Configuration:**
```hcl
# Monitoring Instance Security Group
resource "aws_security_group_rule" "monitoring_egress" {
  type        = "egress"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # New Relic API
}

resource "aws_security_group_rule" "database_access" {
  type                     = "egress"
  from_port                = 3306  # MySQL
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.databases.id
}
```

### 4. Encryption

**Always Enable:**
- TLS for database connections
- Encryption at rest for EBS volumes
- HTTPS for New Relic API communication
- Encrypted backups

## Deployment Best Practices

### 1. Infrastructure as Code

**Terraform Best Practices:**
```hcl
# Use workspaces for environments
terraform workspace new production
terraform workspace new staging

# Use consistent naming
resource "aws_instance" "monitoring" {
  tags = {
    Name        = "${var.environment}-${var.service}-monitoring"
    Environment = var.environment
    Service     = var.service
    ManagedBy   = "terraform"
  }
}

# Pin provider versions
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

### 2. Configuration Management

**Ansible Best Practices:**
```yaml
# Use ansible-vault for sensitive data
ansible-vault encrypt_string 'sensitive_password' --name 'db_password'

# Implement idempotent playbooks
- name: Configure New Relic agent
  template:
    src: newrelic-infra.yml.j2
    dest: /etc/newrelic-infra.yml
  notify: restart newrelic-infra
  
# Use handlers for service management
handlers:
  - name: restart newrelic-infra
    systemd:
      name: newrelic-infra
      state: restarted
      daemon_reload: yes
```

### 3. Deployment Strategy

**Recommended Approach:**
```bash
# 1. Test in development
./deploy-monitoring.sh --environment dev

# 2. Validate in staging
./deploy-monitoring.sh --environment staging

# 3. Production deployment with approval
./deploy-monitoring.sh --environment prod --require-approval

# 4. Verify deployment
./verify-deployment.sh --environment prod
```

## Database Configuration

### 1. Query Performance Setup

**PostgreSQL Configuration:**
```ini
# postgresql.conf
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
pg_stat_statements.track_utility = off
pg_stat_statements.max = 10000
track_activity_query_size = 2048

# Enable logging for analysis
log_min_duration_statement = 1000  # Log queries over 1 second
log_line_prefix = '%t [%p]: [%l-1] db=%d,user=%u,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
```

**MySQL Configuration:**
```ini
# my.cnf
[mysqld]
# Enable performance schema
performance_schema = ON
performance_schema_consumer_events_statements_current = ON
performance_schema_consumer_events_statements_history = ON
performance_schema_consumer_events_statements_history_long = ON

# Query monitoring
long_query_time = 1
slow_query_log = ON
log_queries_not_using_indexes = ON

# Increase history size
performance_schema_events_statements_history_size = 100
performance_schema_events_statements_history_long_size = 10000
```

### 2. Connection Management

**Best Practices:**
- Use connection pooling
- Set appropriate timeouts
- Monitor connection usage
- Implement retry logic

## Monitoring Configuration

### 1. Collection Intervals

**Optimize for Your Needs:**
```yaml
# High-frequency monitoring (Critical databases)
mysql_databases:
  - host: critical-db.example.com
    interval: 30s
    enable_extended_metrics: true

# Standard monitoring (Most databases)
mysql_databases:
  - host: standard-db.example.com
    interval: 60s
    enable_extended_metrics: false

# Low-frequency monitoring (Development)
mysql_databases:
  - host: dev-db.example.com
    interval: 300s
    enable_extended_metrics: false
```

### 2. Custom Metrics

**Define Business-Relevant Metrics:**
```yaml
custom_queries:
  - name: active_user_sessions
    query: |
      SELECT COUNT(*) as value 
      FROM user_sessions 
      WHERE last_activity > NOW() - INTERVAL 5 MINUTE
    interval: 60s
    
  - name: order_processing_queue
    query: |
      SELECT COUNT(*) as value 
      FROM orders 
      WHERE status = 'pending'
    interval: 30s
```

### 3. Label Strategy

**Consistent Labeling:**
```yaml
databases:
  - host: prod-mysql-01.example.com
    custom_labels:
      environment: production
      region: us-east-1
      team: platform
      service: user-api
      tier: primary
      datacenter: aws
```

## Operational Excellence

### 1. Monitoring Health Checks

**Implement Monitoring Validation:**
```bash
#!/bin/bash
# health-check.sh

# Check agent status
if ! systemctl is-active --quiet newrelic-infra; then
  echo "ERROR: New Relic agent is not running"
  exit 1
fi

# Verify database connectivity
for db in $(cat /etc/newrelic-infra/integrations.d/mysql-config.yml | grep host | awk '{print $2}'); do
  if ! mysqladmin -h "$db" -u newrelic ping &>/dev/null; then
    echo "ERROR: Cannot connect to database $db"
    exit 1
  fi
done

# Check metrics collection
last_metric=$(find /var/log/newrelic-infra/ -name "*.log" -mmin -5 | wc -l)
if [ "$last_metric" -eq 0 ]; then
  echo "WARNING: No recent metric collection"
fi
```

### 2. Alerting Strategy

**Recommended Alerts:**
```yaml
Critical Alerts:
  - Agent Down: No data received for 5 minutes
  - Database Unreachable: Connection failures
  - High Error Rate: Query errors > 5%
  - Replication Lag: > 60 seconds

Warning Alerts:
  - Slow Queries: Average duration > 5 seconds
  - Connection Saturation: > 80% of max_connections
  - Lock Waits: > 10 per minute
  - Cache Hit Ratio: < 90%
```

### 3. Runbook Documentation

**Standard Operating Procedures:**
```markdown
## Database Monitoring Runbook

### Agent Not Reporting
1. SSH to monitoring instance
2. Check agent status: `systemctl status newrelic-infra`
3. Review logs: `journalctl -u newrelic-infra -n 100`
4. Verify network connectivity
5. Restart if needed: `systemctl restart newrelic-infra`

### Missing Database Metrics
1. Test database connectivity from monitoring host
2. Verify database user permissions
3. Check integration configuration
4. Review integration logs
5. Validate custom queries
```

## Performance Optimization

### 1. Query Optimization

**Optimize Monitoring Queries:**
```sql
-- Use indexes for monitoring queries
CREATE INDEX idx_monitoring_timestamp ON audit_log(created_at);

-- Limit result sets
SELECT /* monitoring */ 
  COUNT(*) as active_connections 
FROM information_schema.processlist 
WHERE command != 'Sleep' 
LIMIT 1;

-- Avoid heavy joins in monitoring queries
-- Use summary tables where possible
```

### 2. Resource Management

**Monitoring Instance Optimization:**
```bash
# Tune system parameters
echo "vm.swappiness = 10" >> /etc/sysctl.conf
echo "net.core.rmem_max = 134217728" >> /etc/sysctl.conf
echo "net.core.wmem_max = 134217728" >> /etc/sysctl.conf

# Optimize agent configuration
cat > /etc/newrelic-infra.yml << EOF
log_level: warn  # Reduce logging overhead
payload_compression_level: 6  # Optimize compression
metrics_network_request_timeout: 30s
EOF
```

### 3. Batch Processing

**Efficient Metric Collection:**
```yaml
# Group databases by collection interval
batch_configuration:
  high_priority:
    interval: 30s
    databases: ["prod-primary", "prod-replica"]
    
  standard_priority:
    interval: 60s
    databases: ["app-db-01", "app-db-02"]
    
  low_priority:
    interval: 300s
    databases: ["dev-01", "test-01"]
```

## Troubleshooting Patterns

### 1. Common Issues Matrix

| Issue | Symptoms | Root Cause | Solution |
|-------|----------|------------|----------|
| No Data | Empty dashboards | Agent not running | Restart agent, check logs |
| Partial Data | Some metrics missing | Permission issues | Review database grants |
| High Latency | Delayed metrics | Network issues | Check security groups |
| Connection Errors | Error logs | Firewall/credentials | Verify connectivity |

### 2. Debug Mode

**Enable Verbose Logging:**
```yaml
# Temporary debug configuration
log_level: debug
verbose: 1
trace:
  enabled: true
  file: /var/log/newrelic-infra-trace.log
```

### 3. Validation Scripts

**Pre-deployment Validation:**
```bash
#!/bin/bash
# validate-deployment.sh

echo "=== Pre-deployment Validation ==="

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  echo "❌ AWS credentials not configured"
  exit 1
fi

# Validate Terraform
cd terraform/
if ! terraform validate; then
  echo "❌ Terraform configuration invalid"
  exit 1
fi

# Check Ansible syntax
cd ../ansible/
if ! ansible-playbook --syntax-check playbooks/install-newrelic.yml; then
  echo "❌ Ansible playbook syntax error"
  exit 1
fi

echo "✅ All validations passed"
```

## Summary

Following these best practices will ensure:
- **Reliable Monitoring**: Consistent data collection
- **Secure Operations**: Protected credentials and connections
- **Optimal Performance**: Efficient resource utilization
- **Easy Maintenance**: Clear procedures and documentation
- **Rapid Troubleshooting**: Effective problem resolution

Remember: Start simple, validate often, and scale gradually. The best monitoring setup is one that provides valuable insights without adding operational overhead.

---

*For additional guidance, visit the [New Relic Documentation](https://docs.newrelic.com) or contact our support team.*