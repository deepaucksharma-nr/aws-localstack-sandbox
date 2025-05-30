#!/bin/bash
# Quick start script for AWS Database Monitoring with LocalStack

set -e

echo "================================================"
echo "AWS Database Monitoring - Quick Start"
echo "================================================"
echo ""
echo "This script will:"
echo "1. Check prerequisites"
echo "2. Start LocalStack and databases"
echo "3. Initialize AWS resources"
echo "4. Run a simple test"
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    echo "   Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check docker-compose
if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose is not installed. Please install it first."
    echo "   Visit: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "✅ Prerequisites checked"
echo ""

# Check for secrets
if [ ! -d "secrets" ]; then
    echo "Generating secure secrets..."
    ./scripts/generate-secrets.sh
fi

# Start services
echo "Starting LocalStack and databases..."
docker-compose up -d localstack mysql-test postgres-test newrelic-mock

# Wait for LocalStack
echo "Waiting for LocalStack to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:4566/_localstack/health | grep -q "running"; then
        echo "✅ LocalStack is ready"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Initialize LocalStack
echo "Initializing AWS resources in LocalStack..."
docker exec localstack bash -c "
    chmod +x /docker-entrypoint-initaws.d/*.sh
    /docker-entrypoint-initaws.d/init-aws.sh
" > /tmp/localstack-init.log 2>&1

if [ $? -eq 0 ]; then
    echo "✅ AWS resources initialized"
else
    echo "❌ Failed to initialize AWS resources"
    echo "   Check /tmp/localstack-init.log for details"
    exit 1
fi

# Run a simple test
echo ""
echo "Running configuration test..."
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test

# Get config from SSM
aws --endpoint-url=$AWS_ENDPOINT_URL ssm get-parameter \
    --name "/localstack/newrelic/database-config" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text > /tmp/quickstart-config.json

# Transform it
if python3 scripts/transform-config.py /tmp/quickstart-config.json /tmp/quickstart-config.yml; then
    echo "✅ Configuration transformation successful"
    echo ""
    echo "Transformed configuration:"
    echo "========================="
    head -20 /tmp/quickstart-config.yml
    echo "..."
else
    echo "❌ Configuration transformation failed"
    exit 1
fi

echo ""
echo "================================================"
echo "✅ Quick Start Complete!"
echo "================================================"
echo ""
echo "LocalStack is running with:"
echo "- VPC and networking configured"
echo "- IAM roles and policies created"
echo "- Secrets stored in Secrets Manager"
echo "- Database configuration in SSM"
echo "- MySQL running on localhost:3306"
echo "- PostgreSQL running on localhost:5432"
echo ""
echo "Next steps:"
echo "1. Run the full demo:        make localstack-demo"
echo "2. Run Terraform:            cd terraform && terraform apply -var-file=terraform.localstack.tfvars"
echo "3. Validate everything:      ./test/verify-localstack-setup.sh"
echo "4. Read the documentation:   cat LOCALSTACK_README.md"
echo ""
echo "To stop everything:          docker-compose down"
echo ""