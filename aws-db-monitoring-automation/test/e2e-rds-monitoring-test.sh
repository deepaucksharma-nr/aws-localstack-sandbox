#!/bin/bash

set -euo pipefail

# End-to-End RDS Monitoring Test
# This script simulates the complete setup and verification process

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Test configuration
TEST_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$TEST_DIR")"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     New Relic RDS Monitoring - End-to-End Test               ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

# Step 1: Simulate RDS Database Setup
echo -e "${GREEN}Step 1: Simulating RDS Database Setup${NC}"
echo "In a real deployment, you would have:"
echo "  - RDS MySQL instance: myapp-prod.cluster-xxxxx.us-east-1.rds.amazonaws.com"
echo "  - RDS PostgreSQL instance: analytics-prod.cluster-xxxxx.us-east-1.rds.amazonaws.com"
echo "  - Security groups configured for monitoring access"
echo ""

# Step 2: Create test configuration
echo -e "${GREEN}Step 2: Creating Test Configuration${NC}"

# Create a test databases.yml for RDS
cat > "${PROJECT_ROOT}/config/databases-rds-test.yml" << EOF
# RDS Database Configuration
newrelic_license_key: "test_license_key_40_characters_long_xxxxx"
newrelic_account_id: "1234567"
newrelic_region: "US"

# RDS MySQL Databases
mysql_databases:
  - host: myapp-prod.cluster-xxxxx.us-east-1.rds.amazonaws.com
    port: 3306
    user: newrelic
    password: "secure_mysql_password"
    service_name: rds-mysql-prod
    environment: production
    extended_metrics: true
    enable_query_monitoring: true
    query_metrics_interval: 60s
    interval: 30s
    custom_labels:
      application: myapp
      tier: primary
      region: us-east-1
      db_engine: aurora-mysql

  - host: myapp-replica.cluster-ro-xxxxx.us-east-1.rds.amazonaws.com
    port: 3306
    user: newrelic
    password: "secure_mysql_password"
    service_name: rds-mysql-replica
    environment: production
    extended_metrics: true
    interval: 60s
    custom_labels:
      application: myapp
      tier: replica
      region: us-east-1
      db_engine: aurora-mysql

# RDS PostgreSQL Databases
postgresql_databases:
  - host: analytics-prod.cluster-xxxxx.us-east-1.rds.amazonaws.com
    port: 5432
    user: newrelic
    password: "secure_pg_password"
    database: analytics
    service_name: rds-postgres-analytics
    environment: production
    sslmode: require
    collect_bloat_metrics: true
    collect_db_lock_metrics: true
    enable_query_monitoring: true
    query_metrics_interval: 60s
    interval: 30s
    custom_labels:
      application: analytics
      tier: primary
      region: us-east-1
      db_engine: aurora-postgresql

  - host: reporting.xxxxx.us-east-1.rds.amazonaws.com
    port: 5432
    user: newrelic
    password: "secure_pg_password"
    database: reporting
    service_name: rds-postgres-reporting
    environment: production
    sslmode: require
    interval: 120s
    custom_labels:
      application: reporting
      tier: secondary
      region: us-east-1
      db_engine: postgres
EOF

echo "Created test RDS configuration: config/databases-rds-test.yml"
echo ""

# Step 3: Simulate Infrastructure Deployment
echo -e "${GREEN}Step 3: Simulating Infrastructure Deployment${NC}"
echo "In a real deployment, Terraform would create:"
echo "  - EC2 monitoring instance (t3.medium)"
echo "  - Security group allowing:"
echo "    - Inbound: SSH (22) from your IP"
echo "    - Outbound: HTTPS (443) to New Relic"
echo "    - Outbound: MySQL (3306) to RDS instances"
echo "    - Outbound: PostgreSQL (5432) to RDS instances"
echo "  - IAM role with permissions for Secrets Manager"
echo ""

# Step 4: Show agent installation process
echo -e "${GREEN}Step 4: Agent Installation Process${NC}"
echo "Ansible would install and configure:"
echo "  1. New Relic Infrastructure agent"
echo "  2. MySQL integration (nri-mysql)"
echo "  3. PostgreSQL integration (nri-postgresql)"
echo "  4. Custom query configurations"
echo ""

# Step 5: Show configuration files that would be created
echo -e "${GREEN}Step 5: Configuration Files on Monitoring Instance${NC}"

echo -e "\n${YELLOW}/etc/newrelic-infra.yml:${NC}"
cat << 'EOF'
license_key: test_license_key_40_characters_long_xxxxx
display_name: rds-monitoring-prod
log_level: info
custom_attributes:
  environment: production
  role: database-monitoring
  region: us-east-1
EOF

echo -e "\n${YELLOW}/etc/newrelic-infra/integrations.d/mysql-config.yml:${NC}"
cat << 'EOF'
integrations:
  - name: nri-mysql
    env:
      HOSTNAME: myapp-prod.cluster-xxxxx.us-east-1.rds.amazonaws.com
      PORT: 3306
      USERNAME: newrelic
      PASSWORD: secure_mysql_password
      REMOTE_MONITORING: true
      METRICS: true
      EXTENDED_METRICS: true
      INVENTORY: true
      CUSTOM_METRICS_QUERY_FILE: /etc/newrelic-infra/integrations.d/mysql-custom-queries.yml
      PERFORMANCE_SCHEMA: true
    labels:
      env: production
      database_type: mysql
      service_name: rds-mysql-prod
      db_engine: aurora-mysql
    interval: 30s
EOF

echo -e "\n${YELLOW}/etc/newrelic-infra/integrations.d/postgresql-config.yml:${NC}"
cat << 'EOF'
integrations:
  - name: nri-postgresql
    env:
      HOSTNAME: analytics-prod.cluster-xxxxx.us-east-1.rds.amazonaws.com
      PORT: 5432
      USERNAME: newrelic
      PASSWORD: secure_pg_password
      DATABASE: analytics
      ENABLE_SSL: true
      SSL_MODE: require
      COLLECTION_LIST: 'ALL'
      COLLECT_DB_LOCK_METRICS: true
      COLLECT_BLOAT_METRICS: true
      METRICS: true
      INVENTORY: true
      CUSTOM_METRICS_QUERY_FILE: /etc/newrelic-infra/integrations.d/postgresql-custom-queries.yml
      PG_STAT_STATEMENTS: true
    labels:
      env: production
      database_type: postgresql
      service_name: rds-postgres-analytics
      db_engine: aurora-postgresql
    interval: 30s
EOF

echo ""

# Step 6: Verification Process
echo -e "${GREEN}Step 6: Verification Process${NC}"
echo "To verify the setup is working:"
echo ""
echo "1. SSH to monitoring instance:"
echo "   ${YELLOW}ssh -i ~/.ssh/your-key.pem ec2-user@<instance-ip>${NC}"
echo ""
echo "2. Check agent status:"
echo "   ${YELLOW}sudo systemctl status newrelic-infra${NC}"
echo ""
echo "3. Check logs for data collection:"
echo "   ${YELLOW}sudo journalctl -u newrelic-infra -f | grep -E 'mysql|postgresql'${NC}"
echo ""
echo "4. Test RDS connectivity:"
echo "   ${YELLOW}nc -zv myapp-prod.cluster-xxxxx.us-east-1.rds.amazonaws.com 3306${NC}"
echo ""
echo "5. Run verification script:"
echo "   ${YELLOW}./scripts/verify-rds-monitoring.sh -i <instance-ip> -k ~/.ssh/your-key.pem${NC}"
echo ""

# Step 7: Expected Data in New Relic
echo -e "${GREEN}Step 7: Expected Data in New Relic${NC}"
echo "After 5-10 minutes, you should see in New Relic:"
echo ""
echo "Infrastructure > Third-party services:"
echo "  - MySQL integrations for RDS instances"
echo "  - PostgreSQL integrations for RDS instances"
echo ""
echo "Infrastructure > AWS > RDS:"
echo "  - Your RDS instances with CloudWatch metrics"
echo "  - Enhanced monitoring if enabled"
echo ""
echo "Databases view:"
echo "  - Query performance metrics"
echo "  - Top slow queries"
echo "  - Wait events analysis"
echo "  - Connection statistics"
echo ""

# Step 8: Sample NRQL Queries
echo -e "${GREEN}Step 8: Sample NRQL Queries for RDS Monitoring${NC}"
cat << 'EOF'

# Top slow MySQL queries from RDS
SELECT average(total_time_ms) as 'Avg Time (ms)', 
       sum(calls) as 'Total Calls',
       latest(query_text_sample) as 'Query'
FROM MysqlCustomQuerySample 
WHERE service_name LIKE 'rds-%'
FACET query_text_sample 
SINCE 1 hour ago
LIMIT 10

# RDS PostgreSQL connection monitoring
SELECT average(db.connections) as 'Connections',
       average(db.commitsPerSecond) as 'Commits/sec',
       average(db.cacheHitRatio) as 'Cache Hit %'
FROM PostgresqlSample
WHERE db_engine = 'aurora-postgresql'
TIMESERIES SINCE 1 hour ago

# RDS instance health overview
SELECT latest(provider.cpuUtilization.Average) as 'CPU %',
       latest(provider.databaseConnections.Average) as 'Connections',
       latest(provider.freeStorageSpace.Average) / 1073741824 as 'Free Storage GB'
FROM RdsDbInstance
FACET displayName
SINCE 5 minutes ago
EOF

echo ""

# Step 9: Troubleshooting Tips
echo -e "${GREEN}Step 9: RDS-Specific Troubleshooting${NC}"
echo "Common RDS monitoring issues:"
echo ""
echo "1. ${YELLOW}Security Group Issues:${NC}"
echo "   - Ensure monitoring instance SG has outbound rules for RDS ports"
echo "   - RDS security group must allow inbound from monitoring instance"
echo ""
echo "2. ${YELLOW}SSL/TLS Connection:${NC}"
echo "   - Aurora PostgreSQL requires SSL by default"
echo "   - Download RDS CA certificate if needed"
echo ""
echo "3. ${YELLOW}Parameter Groups:${NC}"
echo "   - For query monitoring, ensure performance_schema=ON (MySQL)"
echo "   - For PostgreSQL, shared_preload_libraries must include pg_stat_statements"
echo ""
echo "4. ${YELLOW}IAM Database Authentication:${NC}"
echo "   - If using IAM auth, monitoring instance needs proper IAM role"
echo ""

# Clean up test file
echo -e "\n${BLUE}Test configuration saved to: config/databases-rds-test.yml${NC}"
echo -e "${BLUE}Review and adapt for your actual RDS instances${NC}"

echo -e "\n${GREEN}End-to-End RDS Monitoring Test Complete!${NC}\n"