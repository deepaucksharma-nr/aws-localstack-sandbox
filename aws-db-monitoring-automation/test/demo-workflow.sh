#!/bin/bash

# Demo Workflow - Shows the complete setup process

set -uo pipefail

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    New Relic Database Monitoring - Demo Workflow              ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

echo -e "${GREEN}Step 1: Initial Setup Verification${NC}"
echo "Running setup verification to check prerequisites..."
echo -e "${YELLOW}Command: ./scripts/setup-verification.sh --verbose${NC}"
echo "(Would check for Terraform, Ansible, AWS CLI, etc.)"
echo

echo -e "${GREEN}Step 2: Configuration Files${NC}"
echo "Setting up configuration files..."
echo -e "${YELLOW}Command: cp terraform/terraform.tfvars.example terraform/terraform.tfvars${NC}"
echo -e "${YELLOW}Command: cp config/databases.example.yml config/databases.yml${NC}"
echo "Files would be edited with actual values"
echo

echo -e "${GREEN}Step 3: Database Preparation${NC}"
echo "Setting up database users and permissions..."
echo -e "${YELLOW}MySQL: mysql -u root -p < scripts/setup-mysql-monitoring.sql${NC}"
echo -e "${YELLOW}PostgreSQL: psql -U postgres -f scripts/setup-postgresql-monitoring.sql${NC}"
echo

echo -e "${GREEN}Step 4: Test Database Connections${NC}"
echo "Testing connections before deployment..."
echo -e "${YELLOW}Command: ./scripts/test-db-connection.sh \\
  --mysql-host mysql.example.com --mysql-pass password \\
  --pg-host postgres.example.com --pg-pass password${NC}"
echo

echo -e "${GREEN}Step 5: Deploy Infrastructure${NC}"
echo "Deploying monitoring infrastructure..."
echo -e "${YELLOW}Command: ./scripts/deploy-monitoring.sh -k ~/.ssh/my-key.pem${NC}"
echo "This would:"
echo "  - Run pre-flight checks"
echo "  - Create EC2 instance with Terraform"
echo "  - Install New Relic agent with Ansible"
echo "  - Configure database integrations"
echo

echo -e "${GREEN}Step 6: Validate Query Monitoring${NC}"
echo "Validating query monitoring setup..."
echo -e "${YELLOW}Command: ./scripts/validate-query-monitoring.sh \\
  --mysql-host mysql.example.com --mysql-pass password${NC}"
echo

echo -e "${GREEN}Step 7: Monitor in New Relic${NC}"
echo "Data would appear in:"
echo "  - Infrastructure: https://one.newrelic.com/infrastructure"
echo "  - Databases: https://one.newrelic.com/infrastructure/databases"
echo "  - Query Performance: Database entity views"
echo

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Demo Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

echo "Key Features Demonstrated:"
echo "✓ Step-by-step verification process"
echo "✓ Pre-flight checks before deployment"
echo "✓ Database connection testing"
echo "✓ Query performance monitoring setup"
echo "✓ Comprehensive troubleshooting tools"
echo

echo "Files Created/Updated:"
echo "- setup-verification.sh: 10-step verification process"
echo "- deploy-monitoring.sh: Enhanced with pre-flight checks"
echo "- test-db-connection.sh: Database connectivity testing"
echo "- validate-query-monitoring.sh: Query monitoring validation"
echo "- MySQL/PostgreSQL custom query templates"
echo "- Comprehensive documentation (QUICK_START, TROUBLESHOOTING, etc.)"
echo

echo -e "${YELLOW}To run actual deployment:${NC}"
echo "1. Install prerequisites (Terraform, Ansible, AWS CLI)"
echo "2. Configure AWS credentials"
echo "3. Update configuration files with real values"
echo "4. Run: ./scripts/deploy-monitoring.sh -k your-key.pem"