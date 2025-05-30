#!/bin/bash
# Userdata script for staging monitoring instance

set -e

# Variables from Terraform
ENVIRONMENT="${environment}"
NEWRELIC_LICENSE_KEY="${newrelic_license_key}"

# Update system
yum update -y

# Install required packages
yum install -y \
  python3 \
  python3-pip \
  mysql \
  postgresql \
  jq \
  git

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws/

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
EOF

# Install database integrations
yum install -y nri-mysql nri-postgresql

# Create directory for custom queries
mkdir -p /etc/newrelic-infra/integrations.d

# Download database configuration from SSM
aws ssm get-parameter \
  --name "/$${ENVIRONMENT}/newrelic/database-config" \
  --query 'Parameter.Value' \
  --output text \
  --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) \
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

# Start New Relic Infrastructure service
systemctl enable newrelic-infra
systemctl start newrelic-infra

# Log completion
echo "Monitoring instance setup completed at $(date)" >> /var/log/setup.log