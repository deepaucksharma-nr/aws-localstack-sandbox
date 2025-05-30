#!/bin/bash
# Enhanced userdata script template for Terraform
# Variables are interpolated by Terraform's templatefile()

set -e

# Log output to file and console
exec > >(tee -a /var/log/userdata.log)
exec 2>&1

echo "Starting enhanced userdata script at $(date)"

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
ENVIRONMENT="${environment}"

# Update system
echo "Updating system packages..."
yum update -y

# Install required packages
echo "Installing required packages..."
yum install -y \
  python3 \
  python3-pip \
  git \
  jq \
  mysql \
  postgresql \
  amazon-cloudwatch-agent

# Install Python packages
pip3 install \
  ansible \
  boto3 \
  pyyaml \
  requests

# Install AWS CLI v2
echo "Installing AWS CLI v2..."
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf awscliv2.zip aws/
fi

# Install New Relic repository
echo "Setting up New Relic repository..."
curl -o /etc/yum.repos.d/newrelic-infra.repo \
    https://download.newrelic.com/infrastructure_agent/linux/yum/el/7/x86_64/newrelic-infra.repo

# Set environment variables for New Relic
export NEWRELIC_LICENSE_KEY="${newrelic_license_key}"
export NEWRELIC_ACCOUNT_ID="${newrelic_account_id}"

# Download transformation script
echo "Setting up configuration transformation..."
cat > /usr/local/bin/transform-config.py <<'SCRIPT'
${file("${path.module}/../scripts/transform-config.py")}
SCRIPT
chmod +x /usr/local/bin/transform-config.py

# Handle configuration based on source
%{ if ssm_config_parameter != "" ~}
# Using SSM parameter for configuration
echo "Fetching configuration from SSM parameter: ${ssm_config_parameter}"

aws ssm get-parameter \
    --name "${ssm_config_parameter}" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text \
    --region "$REGION" \
    > /tmp/database-config.json

# Transform configuration
echo "Transforming configuration..."
python3 /usr/local/bin/transform-config.py \
    /tmp/database-config.json \
    /tmp/databases.yml \
    --region "$REGION"

CONFIG_FILE="/tmp/databases.yml"

%{ else ~}
# Using inline configuration
echo "Using inline configuration..."
cat > /tmp/databases.yml <<'CONFIG'
newrelic_license_key: "${newrelic_license_key}"
newrelic_account_id: "${newrelic_account_id}"
%{ if length(mysql_databases) > 0 ~}
mysql_databases:
%{ for db in mysql_databases ~}
  - host: ${db.host}
    port: ${db.port}
    user: ${db.user}
    password: ${db.password}
    service_name: ${db.service_name}
    environment: ${environment}
    extended_metrics: ${db.extended_metrics}
    enable_query_monitoring: ${db.enable_query_monitoring}
%{ endfor ~}
%{ endif ~}
%{ if length(postgresql_databases) > 0 ~}
postgresql_databases:
%{ for db in postgresql_databases ~}
  - host: ${db.host}
    port: ${db.port}
    user: ${db.user}
    password: ${db.password}
    database: ${db.database}
    service_name: ${db.service_name}
    environment: ${environment}
    sslmode: ${db.sslmode}
    collect_bloat_metrics: ${db.collect_bloat_metrics}
    enable_query_monitoring: ${db.enable_query_monitoring}
%{ endfor ~}
%{ endif ~}
CONFIG

CONFIG_FILE="/tmp/databases.yml"
%{ endif ~}

# Verify configuration
echo "Configuration file contents:"
cat "$CONFIG_FILE"

# Create Ansible inventory
cat > /tmp/ansible-inventory.ini <<EOF
[monitoring_server]
localhost ansible_connection=local
EOF

# Download Ansible playbooks and templates
echo "Setting up Ansible files..."
mkdir -p /opt/ansible/{playbooks,templates}

# Download playbook
curl -sSL -o /opt/ansible/playbooks/install-newrelic.yml \
    "${ansible_playbook_url}"

# Download templates
for template in ${join(" ", ansible_templates)}; do
    curl -sSL -o "/opt/ansible/templates/$template" \
        "${ansible_templates_base_url}/$template"
done

# Run Ansible playbook with retries
echo "Running Ansible playbook..."
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_RETRY_FILES_ENABLED=False

MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES..."
    
    if ansible-playbook \
        -i /tmp/ansible-inventory.ini \
        -e "@$CONFIG_FILE" \
        /opt/ansible/playbooks/install-newrelic.yml; then
        echo "Ansible playbook completed successfully!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "Ansible playbook failed, retrying in 30 seconds..."
            sleep 30
        else
            echo "ERROR: Ansible playbook failed after $MAX_RETRIES attempts!"
            exit 1
        fi
    fi
done

# Configure CloudWatch agent
echo "Configuring CloudWatch agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CW_CONFIG'
${cloudwatch_config}
CW_CONFIG

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Verify services
echo "Verifying services..."
sleep 10

# Check New Relic agent
if systemctl is-active --quiet newrelic-infra; then
    echo "SUCCESS: New Relic Infrastructure agent is running!"
else
    echo "ERROR: New Relic Infrastructure agent is not running!"
    journalctl -u newrelic-infra -n 50
fi

# Tag instance
echo "Tagging instance..."
aws ec2 create-tags \
    --resources "$INSTANCE_ID" \
    --tags \
        Key=NewRelicMonitoring,Value=Configured \
        Key=ConfigurationSource,Value="${ssm_config_parameter != "" ? "ssm" : "inline"}" \
        Key=Environment,Value="$ENVIRONMENT" \
        Key=SetupComplete,Value="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --region "$REGION" || true

# Create completion marker
echo "Setup completed at $(date)" > /var/lib/newrelic-monitoring-setup-complete

echo "Enhanced userdata script completed successfully!"