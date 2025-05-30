#!/bin/bash
# Enhanced userdata script with configuration transformation and credential resolution

set -e

# Log output to file and console
exec > >(tee -a /var/log/userdata.log)
exec 2>&1

echo "Starting enhanced userdata script at $(date)"

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
ENVIRONMENT="${environment:-production}"

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
  postgresql

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

# Clone the monitoring repository (or copy from S3)
echo "Setting up monitoring configuration..."
WORK_DIR="/opt/db-monitoring"
mkdir -p $WORK_DIR
cd $WORK_DIR

# Option 1: Clone from git (if repository URL is provided)
if [ -n "${git_repository}" ]; then
    echo "Cloning repository from ${git_repository}..."
    git clone "${git_repository}" .
fi

# Option 2: Download from S3 (if S3 path is provided)
if [ -n "${s3_config_path}" ]; then
    echo "Downloading configuration from ${s3_config_path}..."
    aws s3 cp "${s3_config_path}" . --recursive
fi

# Check if we should use SSM configuration
if [ -n "${ssm_config_parameter}" ]; then
    echo "Fetching configuration from SSM parameter: ${ssm_config_parameter}"
    
    # Download configuration from SSM
    aws ssm get-parameter \
        --name "${ssm_config_parameter}" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text \
        --region "$REGION" \
        > /tmp/database-config.json
    
    # Check if transformation script exists locally
    if [ -f "scripts/transform-config.py" ]; then
        TRANSFORM_SCRIPT="scripts/transform-config.py"
    else
        # Download transformation script
        echo "Downloading configuration transformation script..."
        curl -o /tmp/transform-config.py \
            "https://raw.githubusercontent.com/newrelic/aws-db-monitoring-automation/main/scripts/transform-config.py"
        chmod +x /tmp/transform-config.py
        TRANSFORM_SCRIPT="/tmp/transform-config.py"
    fi
    
    # Set environment variables for New Relic
    export NEWRELIC_LICENSE_KEY="${newrelic_license_key}"
    export NEWRELIC_ACCOUNT_ID="${newrelic_account_id:-YOUR_ACCOUNT_ID}"
    
    # Transform configuration
    echo "Transforming configuration..."
    python3 "$TRANSFORM_SCRIPT" \
        /tmp/database-config.json \
        /tmp/databases.yml \
        --region "$REGION"
    
    # Use transformed configuration
    CONFIG_FILE="/tmp/databases.yml"
    
elif [ -f "config/databases.yml" ]; then
    # Use static configuration file
    echo "Using static configuration file..."
    CONFIG_FILE="config/databases.yml"
else
    echo "ERROR: No configuration source found!"
    echo "Please provide either:"
    echo "  - ssm_config_parameter in terraform"
    echo "  - config/databases.yml in repository"
    exit 1
fi

# Verify configuration exists and is valid
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

echo "Configuration file contents:"
cat "$CONFIG_FILE"

# Create Ansible inventory
cat > /tmp/ansible-inventory.ini <<EOF
[monitoring_server]
localhost ansible_connection=local
EOF

# Run Ansible playbook
echo "Running Ansible playbook..."
if [ -f "ansible/playbooks/install-newrelic.yml" ]; then
    PLAYBOOK="ansible/playbooks/install-newrelic.yml"
else
    # Download playbook if not present
    echo "Downloading Ansible playbook..."
    mkdir -p /tmp/ansible/playbooks /tmp/ansible/templates
    curl -o /tmp/ansible/playbooks/install-newrelic.yml \
        "https://raw.githubusercontent.com/newrelic/aws-db-monitoring-automation/main/ansible/playbooks/install-newrelic.yml"
    
    # Download templates
    for template in newrelic-infra.yml.j2 mysql-config.yml.j2 postgresql-config.yml.j2 \
                   mysql-custom-queries.yml.j2 postgresql-custom-queries.yml.j2; do
        curl -o "/tmp/ansible/templates/$template" \
            "https://raw.githubusercontent.com/newrelic/aws-db-monitoring-automation/main/ansible/templates/$template"
    done
    
    PLAYBOOK="/tmp/ansible/playbooks/install-newrelic.yml"
fi

# Set Ansible environment
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_RETRY_FILES_ENABLED=False

# Run Ansible with error handling
MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES..."
    
    if ansible-playbook \
        -i /tmp/ansible-inventory.ini \
        -e "@$CONFIG_FILE" \
        "$PLAYBOOK"; then
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

# Verify New Relic agent is running
echo "Verifying New Relic agent status..."
sleep 10

if systemctl is-active --quiet newrelic-infra; then
    echo "SUCCESS: New Relic Infrastructure agent is running!"
    systemctl status newrelic-infra
else
    echo "ERROR: New Relic Infrastructure agent is not running!"
    journalctl -u newrelic-infra -n 50
    exit 1
fi

# Check for configuration errors
echo "Checking for configuration errors..."
if journalctl -u newrelic-infra --since "5 minutes ago" | grep -i error; then
    echo "WARNING: Errors found in New Relic agent logs"
    echo "Recent errors:"
    journalctl -u newrelic-infra --since "5 minutes ago" | grep -i error | tail -20
fi

# Tag instance for identification
echo "Tagging instance..."
aws ec2 create-tags \
    --resources "$INSTANCE_ID" \
    --tags \
        Key=NewRelicMonitoring,Value=Configured \
        Key=ConfigurationSource,Value="${ssm_config_parameter:-static}" \
        Key=Environment,Value="$ENVIRONMENT" \
    --region "$REGION" || true

# Create completion marker
echo "Setup completed at $(date)" > /var/lib/newrelic-monitoring-setup-complete

echo "Enhanced userdata script completed successfully!"
echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"
echo "Configuration source: ${ssm_config_parameter:-static file}"

# Send custom event to New Relic (if agent is configured)
if command -v newrelic-infra-ctl &> /dev/null; then
    newrelic-infra-ctl notify <<EOF
{
  "eventType": "MonitoringSetupComplete",
  "instanceId": "$INSTANCE_ID",
  "region": "$REGION",
  "environment": "$ENVIRONMENT",
  "configSource": "${ssm_config_parameter:-static}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
fi