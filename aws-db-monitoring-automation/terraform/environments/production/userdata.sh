#!/bin/bash
# Userdata script for production monitoring instances

set -e

# Variables from Terraform
ENVIRONMENT="${environment}"
NEWRELIC_LICENSE_KEY="${newrelic_license_key}"
MYSQL_CLUSTER="${mysql_cluster}"
POSTGRES_CLUSTER="${postgres_cluster}"

# Update system
yum update -y

# Install required packages
yum install -y \
  python3 \
  python3-pip \
  mysql \
  postgresql \
  jq \
  git \
  amazon-cloudwatch-agent

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws/

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

# Install New Relic Infrastructure agent
curl -o /etc/yum.repos.d/newrelic-infra.repo \
  https://download.newrelic.com/infrastructure_agent/linux/yum/el/7/x86_64/newrelic-infra.repo
yum -q makecache -y --disablerepo='*' --enablerepo='newrelic-infra'
yum install -y newrelic-infra

# Configure New Relic license key
echo "license_key: $${NEWRELIC_LICENSE_KEY}" > /etc/newrelic-infra.yml

# Add custom attributes
cat >> /etc/newrelic-infra.yml <<EOF
custom_attributes:
  environment: $${ENVIRONMENT}
  role: database-monitoring
  provider: aws
  region: $${REGION}
  availability_zone: $${AZ}
  instance_id: $${INSTANCE_ID}
  cluster_mysql: $${MYSQL_CLUSTER}
  cluster_postgres: $${POSTGRES_CLUSTER}
EOF

# Install database integrations
yum install -y nri-mysql nri-postgresql

# Create directory for custom queries
mkdir -p /etc/newrelic-infra/integrations.d

# Download database configuration from SSM
aws ssm get-parameter \
  --name "/$${ENVIRONMENT}/newrelic/database-config" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region "$${REGION}" \
  > /tmp/database-config.json

# Create helper script for fetching secrets
cat > /usr/local/bin/fetch-secret.sh <<'SCRIPT'
#!/bin/bash
SECRET_ID=$1
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --query SecretString \
  --output text \
  --region "$REGION" 2>/dev/null
SCRIPT
chmod +x /usr/local/bin/fetch-secret.sh

# Create MySQL custom queries file
cat > /etc/newrelic-infra/integrations.d/mysql-custom-queries.yml <<'EOF'
queries:
  - name: MySQLTopSlowQueries
    query: |
      SELECT
        DIGEST_TEXT as query,
        COUNT_STAR as count,
        SUM_TIMER_WAIT/1000000000 as total_time_ms,
        AVG_TIMER_WAIT/1000000000 as avg_time_ms,
        MAX_TIMER_WAIT/1000000000 as max_time_ms
      FROM performance_schema.events_statements_summary_by_digest
      WHERE DIGEST_TEXT NOT LIKE '%performance_schema%'
      ORDER BY SUM_TIMER_WAIT DESC
      LIMIT 10

  - name: MySQLLockWaits
    query: |
      SELECT 
        COUNT(*) as lock_wait_count,
        SUM(TIME) as total_wait_time
      FROM INFORMATION_SCHEMA.INNODB_LOCK_WAITS

  - name: MySQLTableSizes
    query: |
      SELECT 
        table_schema,
        table_name,
        ROUND(((data_length + index_length) / 1024 / 1024), 2) as size_mb
      FROM information_schema.TABLES
      WHERE table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys')
      ORDER BY data_length + index_length DESC
      LIMIT 20
EOF

# Create PostgreSQL custom queries file
cat > /etc/newrelic-infra/integrations.d/postgresql-custom-queries.yml <<'EOF'
queries:
  - name: PostgreSQLTopSlowQueries
    query: |
      SELECT 
        query,
        calls,
        total_exec_time as total_time_ms,
        mean_exec_time as avg_time_ms,
        max_exec_time as max_time_ms
      FROM pg_stat_statements
      WHERE query NOT LIKE '%pg_stat_statements%'
      ORDER BY total_exec_time DESC
      LIMIT 10

  - name: PostgreSQLTableBloat
    query: |
      SELECT
        schemaname,
        tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
        ROUND(100.0 * pg_total_relation_size(schemaname||'.'||tablename) /
              pg_database_size(current_database()), 2) as percent_of_db
      FROM pg_tables
      WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
      ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
      LIMIT 20

  - name: PostgreSQLLongRunningQueries
    query: |
      SELECT
        pid,
        now() - pg_stat_activity.query_start as duration,
        query,
        state
      FROM pg_stat_activity
      WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes'
      AND state != 'idle'
EOF

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "CWAgent",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {
            "name": "cpu_usage_idle",
            "rename": "CPU_USAGE_IDLE",
            "unit": "Percent"
          },
          {
            "name": "cpu_usage_iowait",
            "rename": "CPU_USAGE_IOWAIT",
            "unit": "Percent"
          },
          "cpu_time_guest"
        ],
        "totalcpu": false,
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DISK_USED_PERCENT",
            "unit": "Percent"
          },
          "disk_inodes_free",
          "disk_inodes_used"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          "tcp_established",
          "tcp_time_wait"
        ],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/newrelic-infra/newrelic-infra.log",
            "log_group_name": "/aws/ec2/monitoring/$${ENVIRONMENT}",
            "log_stream_name": "{instance_id}/newrelic-infra.log"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Start New Relic Infrastructure service
systemctl enable newrelic-infra
systemctl start newrelic-infra

# Configure automatic updates
yum install -y yum-cron
sed -i 's/apply_updates = no/apply_updates = yes/' /etc/yum/yum-cron.conf
systemctl enable yum-cron
systemctl start yum-cron

# Log completion
echo "Monitoring instance setup completed at $(date)" >> /var/log/setup.log
echo "Environment: $${ENVIRONMENT}" >> /var/log/setup.log
echo "Instance ID: $${INSTANCE_ID}" >> /var/log/setup.log
echo "Region: $${REGION}" >> /var/log/setup.log
echo "MySQL Cluster: $${MYSQL_CLUSTER}" >> /var/log/setup.log
echo "PostgreSQL Cluster: $${POSTGRES_CLUSTER}" >> /var/log/setup.log