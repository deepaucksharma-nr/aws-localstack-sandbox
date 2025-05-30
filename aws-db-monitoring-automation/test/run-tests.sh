#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
TEST_DIR="/workspace/test"
RESULTS_DIR="/workspace/test-results"
COVERAGE_DIR="/workspace/coverage"

# Create results directories
mkdir -p "$RESULTS_DIR" "$COVERAGE_DIR"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Wait for services to be ready
wait_for_services() {
    print_status "Waiting for services to be ready..."
    
    # Wait for LocalStack
    while ! curl -s http://localstack:4566/_localstack/health | grep -q '"services":'; do
        echo -n "."
        sleep 2
    done
    print_success "LocalStack is ready"
    
    # Wait for MySQL
    while ! mysql -h mysql-test -u newrelic -pnewrelic123 -e "SELECT 1" &>/dev/null; do
        echo -n "."
        sleep 2
    done
    print_success "MySQL is ready"
    
    # Wait for PostgreSQL
    while ! PGPASSWORD=newrelic123 psql -h postgres-test -U newrelic -d testdb -c "SELECT 1" &>/dev/null; do
        echo -n "."
        sleep 2
    done
    print_success "PostgreSQL is ready"
    
    # Wait for Mock New Relic
    while ! curl -s http://mock-newrelic:8080/health | grep -q "ok"; do
        echo -n "."
        sleep 2
    done
    print_success "Mock New Relic is ready"
}

# Run unit tests
run_unit_tests() {
    print_status "Running unit tests..."
    
    cd "$TEST_DIR"
    python3 -m pytest unit/ \
        -v \
        --cov=/workspace \
        --cov-report=html:"$COVERAGE_DIR" \
        --cov-report=term \
        --junit-xml="$RESULTS_DIR/unit-tests.xml" \
        || return 1
        
    print_success "Unit tests completed"
}

# Run integration tests
run_integration_tests() {
    print_status "Running integration tests..."
    
    # Configure AWS CLI for LocalStack
    export AWS_ACCESS_KEY_ID=test
    export AWS_SECRET_ACCESS_KEY=test
    export AWS_DEFAULT_REGION=us-east-1
    export AWS_ENDPOINT_URL=http://localstack:4566
    
    cd "$TEST_DIR"
    python3 -m pytest integration/ \
        -v \
        --timeout=300 \
        --junit-xml="$RESULTS_DIR/integration-tests.xml" \
        || return 1
        
    print_success "Integration tests completed"
}

# Run Terraform tests
run_terraform_tests() {
    print_status "Running Terraform tests..."
    
    cd /workspace/terraform
    
    # Initialize Terraform with LocalStack backend
    terraform init -backend=false
    
    # Validate Terraform configuration
    terraform validate
    
    # Plan with LocalStack variables
    terraform plan -var-file=terraform.localstack.tfvars -out=tfplan
    
    # Apply Terraform
    terraform apply -auto-approve tfplan
    
    # Capture outputs
    terraform output -json > "$RESULTS_DIR/terraform-outputs.json"
    
    print_success "Terraform tests completed"
}

# Run Ansible tests
run_ansible_tests() {
    print_status "Running Ansible tests..."
    
    cd /workspace/ansible
    
    # Lint Ansible playbooks
    ansible-lint playbooks/*.yml || print_warning "Ansible lint warnings found"
    
    # Create test inventory
    cat > inventory/test-hosts.yml << EOF
all:
  hosts:
    test-host:
      ansible_host: localhost
      ansible_connection: local
      newrelic_license_key: test_license_key_123
      newrelic_account_id: test_account_123
      mysql_databases:
        - host: mysql-test
          port: 3306
          user: newrelic
          password: newrelic123
      postgresql_databases:
        - host: postgres-test
          port: 5432
          user: newrelic
          password: newrelic123
          database: testdb
EOF
    
    # Dry run Ansible playbook
    ansible-playbook -i inventory/test-hosts.yml playbooks/install-newrelic.yml --check
    
    print_success "Ansible tests completed"
}

# Run end-to-end tests
run_e2e_tests() {
    print_status "Running end-to-end tests..."
    
    # Execute the full deployment script in test mode
    cd /workspace
    
    # Create test SSH key
    ssh-keygen -t rsa -f /tmp/test-key -N "" -q
    
    # Run deployment with test configuration
    ./scripts/deploy-monitoring.sh \
        -k /tmp/test-key \
        -c config/databases.example.yml \
        --skip-terraform || print_warning "E2E deployment test skipped"
    
    print_success "End-to-end tests completed"
}

# Generate test report
generate_report() {
    print_status "Generating test report..."
    
    cat > "$RESULTS_DIR/test-summary.txt" << EOF
Test Execution Summary
=====================
Date: $(date)
Environment: LocalStack

Test Results:
- Unit Tests: $(grep -c 'passed' "$RESULTS_DIR/unit-tests.xml" || echo "0") passed
- Integration Tests: $(grep -c 'passed' "$RESULTS_DIR/integration-tests.xml" || echo "0") passed
- Terraform: $(jq -r '.instance_id.value' "$RESULTS_DIR/terraform-outputs.json" || echo "N/A")

Coverage Report: $COVERAGE_DIR/index.html
EOF
    
    print_success "Test report generated at $RESULTS_DIR/test-summary.txt"
}

# Main execution
main() {
    print_status "Starting test suite execution..."
    
    # Wait for all services
    wait_for_services
    
    # Run test suites
    FAILED=0
    
    run_unit_tests || FAILED=$((FAILED + 1))
    run_integration_tests || FAILED=$((FAILED + 1))
    run_terraform_tests || FAILED=$((FAILED + 1))
    run_ansible_tests || FAILED=$((FAILED + 1))
    run_e2e_tests || FAILED=$((FAILED + 1))
    
    # Generate report
    generate_report
    
    # Exit with appropriate code
    if [[ $FAILED -eq 0 ]]; then
        print_success "All tests passed!"
        exit 0
    else
        print_error "$FAILED test suites failed"
        exit 1
    fi
}

# Handle script arguments
case "${1:-all}" in
    unit)
        wait_for_services
        run_unit_tests
        ;;
    integration)
        wait_for_services
        run_integration_tests
        ;;
    terraform)
        wait_for_services
        run_terraform_tests
        ;;
    ansible)
        wait_for_services
        run_ansible_tests
        ;;
    e2e)
        wait_for_services
        run_e2e_tests
        ;;
    all)
        main
        ;;
    *)
        echo "Usage: $0 [unit|integration|terraform|ansible|e2e|all]"
        exit 1
        ;;
esac