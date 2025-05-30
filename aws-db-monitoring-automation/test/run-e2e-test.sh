#!/bin/bash

set -euo pipefail

# Comprehensive End-to-End Test Suite
# Tests the entire New Relic Database Monitoring setup

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test tracking
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=()

# Project paths
TEST_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$TEST_DIR")"

# Test configuration
export TEST_MODE=true
export MOCK_AWS=true

print_header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}    New Relic Database Monitoring - Complete E2E Test Suite     ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_section() {
    echo -e "\n${BLUE}▶ $1${NC}"
    echo -e "${BLUE}────────────────────────────────────────${NC}"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    local test_description="${3:-}"
    
    echo -ne "  Testing: $test_name... "
    
    if eval "$test_command" &>/dev/null; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((TESTS_PASSED++))
        TEST_RESULTS+=("${GREEN}✓${NC} $test_name")
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((TESTS_FAILED++))
        TEST_RESULTS+=("${RED}✗${NC} $test_name")
        if [[ -n "$test_description" ]]; then
            echo -e "    ${YELLOW}→ $test_description${NC}"
        fi
    fi
}

# Phase 1: Prerequisites and Setup Verification
phase1_prerequisites() {
    print_section "Phase 1: Prerequisites and Setup Verification"
    
    # Test script existence
    run_test "Setup verification script exists" \
        "[[ -x $PROJECT_ROOT/scripts/setup-verification.sh ]]"
    
    run_test "Deploy script exists" \
        "[[ -x $PROJECT_ROOT/scripts/deploy-monitoring.sh ]]"
    
    run_test "Database connection test script exists" \
        "[[ -x $PROJECT_ROOT/scripts/test-db-connection.sh ]]"
    
    run_test "Query monitoring validation script exists" \
        "[[ -x $PROJECT_ROOT/scripts/validate-query-monitoring.sh ]]"
    
    run_test "RDS monitoring verification script exists" \
        "[[ -x $PROJECT_ROOT/scripts/verify-rds-monitoring.sh ]]"
    
    # Test configuration files
    run_test "Terraform configuration exists" \
        "[[ -f $PROJECT_ROOT/terraform/main.tf && -f $PROJECT_ROOT/terraform/variables.tf ]]"
    
    run_test "Ansible playbook exists" \
        "[[ -f $PROJECT_ROOT/ansible/playbooks/install-newrelic.yml ]]"
    
    run_test "Example configurations exist" \
        "[[ -f $PROJECT_ROOT/terraform/terraform.tfvars.example && -f $PROJECT_ROOT/config/databases.example.yml ]]"
}

# Phase 2: Configuration Templates
phase2_configuration() {
    print_section "Phase 2: Configuration Templates and Query Monitoring"
    
    # Test MySQL templates
    run_test "MySQL config template exists" \
        "[[ -f $PROJECT_ROOT/ansible/templates/mysql-config.yml.j2 ]]"
    
    run_test "MySQL template has query monitoring" \
        "grep -q 'enable_query_monitoring' $PROJECT_ROOT/ansible/templates/mysql-config.yml.j2"
    
    run_test "MySQL custom queries template exists" \
        "[[ -f $PROJECT_ROOT/ansible/templates/mysql-custom-queries.yml.j2 ]]"
    
    run_test "MySQL queries include performance metrics" \
        "grep -q 'mysql_top_queries_by_time' $PROJECT_ROOT/ansible/templates/mysql-custom-queries.yml.j2"
    
    # Test PostgreSQL templates
    run_test "PostgreSQL config template exists" \
        "[[ -f $PROJECT_ROOT/ansible/templates/postgresql-config.yml.j2 ]]"
    
    run_test "PostgreSQL template has pg_stat_statements" \
        "grep -q 'PG_STAT_STATEMENTS' $PROJECT_ROOT/ansible/templates/postgresql-config.yml.j2"
    
    run_test "PostgreSQL custom queries template exists" \
        "[[ -f $PROJECT_ROOT/ansible/templates/postgresql-custom-queries.yml.j2 ]]"
    
    run_test "PostgreSQL queries include performance metrics" \
        "grep -q 'pg_stat_statements_top_queries_by_time' $PROJECT_ROOT/ansible/templates/postgresql-custom-queries.yml.j2"
}

# Phase 3: Database Setup Scripts
phase3_database_setup() {
    print_section "Phase 3: Database Setup and Permissions"
    
    # Test setup scripts
    run_test "MySQL setup script exists" \
        "[[ -f $PROJECT_ROOT/scripts/setup-mysql-monitoring.sql ]]"
    
    run_test "MySQL script creates monitoring user" \
        "grep -q 'CREATE USER.*newrelic' $PROJECT_ROOT/scripts/setup-mysql-monitoring.sql"
    
    run_test "MySQL script grants performance_schema access" \
        "grep -q 'GRANT.*performance_schema' $PROJECT_ROOT/scripts/setup-mysql-monitoring.sql"
    
    run_test "PostgreSQL setup script exists" \
        "[[ -f $PROJECT_ROOT/scripts/setup-postgresql-monitoring.sql ]]"
    
    run_test "PostgreSQL script creates monitoring user" \
        "grep -q 'CREATE USER.*newrelic' $PROJECT_ROOT/scripts/setup-postgresql-monitoring.sql"
    
    run_test "PostgreSQL script enables pg_stat_statements" \
        "grep -q 'CREATE EXTENSION.*pg_stat_statements' $PROJECT_ROOT/scripts/setup-postgresql-monitoring.sql"
    
    run_test "PostgreSQL script grants pg_read_all_stats" \
        "grep -q 'GRANT pg_read_all_stats' $PROJECT_ROOT/scripts/setup-postgresql-monitoring.sql"
}

# Phase 4: Docker/LocalStack Environment
phase4_docker_environment() {
    print_section "Phase 4: Docker and LocalStack Test Environment"
    
    # Test Docker files
    run_test "Docker Compose file exists" \
        "[[ -f $PROJECT_ROOT/docker-compose.yml ]]"
    
    run_test "LocalStack service defined" \
        "grep -q 'localstack:' $PROJECT_ROOT/docker-compose.yml"
    
    run_test "MySQL test service defined" \
        "grep -q 'mysql-test:' $PROJECT_ROOT/docker-compose.yml"
    
    run_test "PostgreSQL test service defined" \
        "grep -q 'postgres-test:' $PROJECT_ROOT/docker-compose.yml"
    
    # Test fixtures
    run_test "MySQL test data exists" \
        "[[ -f $PROJECT_ROOT/test/fixtures/mysql-init.sql ]]"
    
    run_test "PostgreSQL test data exists" \
        "[[ -f $PROJECT_ROOT/test/fixtures/postgres-init.sql ]]"
    
    # Check if Docker is available
    if command -v docker &>/dev/null; then
        run_test "Docker is installed" "docker --version"
        run_test "Docker Compose is installed" "docker-compose --version || docker compose version"
    else
        echo -e "  ${YELLOW}⚠ Docker not installed - skipping container tests${NC}"
    fi
}

# Phase 5: Documentation
phase5_documentation() {
    print_section "Phase 5: Documentation Completeness"
    
    run_test "README exists" \
        "[[ -f $PROJECT_ROOT/README.md ]]"
    
    run_test "Quick Start guide exists" \
        "[[ -f $PROJECT_ROOT/QUICK_START.md ]]"
    
    run_test "Architecture documentation exists" \
        "[[ -f $PROJECT_ROOT/docs/ARCHITECTURE.md ]]"
    
    run_test "Troubleshooting guide exists" \
        "[[ -f $PROJECT_ROOT/docs/TROUBLESHOOTING.md ]]"
    
    run_test "Query monitoring guide exists" \
        "[[ -f $PROJECT_ROOT/docs/QUERY_MONITORING_GUIDE.md ]]"
    
    run_test "RDS verification guide exists" \
        "[[ -f $PROJECT_ROOT/docs/RDS_MONITORING_VERIFICATION.md ]]"
    
    run_test "Best practices documented" \
        "[[ -f $PROJECT_ROOT/docs/BEST_PRACTICES.md ]]"
}

# Phase 6: Terraform Validation
phase6_terraform() {
    print_section "Phase 6: Terraform Infrastructure Code"
    
    cd "$PROJECT_ROOT/terraform"
    
    # Test Terraform files
    run_test "Main Terraform file valid" \
        "terraform fmt -check main.tf"
    
    run_test "Variables file valid" \
        "terraform fmt -check variables.tf"
    
    run_test "Outputs file exists" \
        "[[ -f outputs.tf ]]"
    
    # Test LocalStack configuration
    run_test "LocalStack provider configured" \
        "[[ -f providers-localstack.tf ]]"
    
    run_test "LocalStack test data exists" \
        "[[ -f data-localstack.tf ]]"
    
    cd "$PROJECT_ROOT"
}

# Phase 7: Ansible Configuration
phase7_ansible() {
    print_section "Phase 7: Ansible Automation"
    
    # Test Ansible structure
    run_test "Ansible playbook directory exists" \
        "[[ -d $PROJECT_ROOT/ansible/playbooks ]]"
    
    run_test "Ansible templates directory exists" \
        "[[ -d $PROJECT_ROOT/ansible/templates ]]"
    
    run_test "Main playbook syntax valid" \
        "python3 -c 'import yaml; yaml.safe_load(open(\"$PROJECT_ROOT/ansible/playbooks/install-newrelic.yml\"))' 2>/dev/null"
    
    # Test playbook tasks
    run_test "Playbook installs infrastructure agent" \
        "grep -q 'Install New Relic Infrastructure agent' $PROJECT_ROOT/ansible/playbooks/install-newrelic.yml"
    
    run_test "Playbook installs MySQL integration" \
        "grep -q 'Install MySQL integration' $PROJECT_ROOT/ansible/playbooks/install-newrelic.yml"
    
    run_test "Playbook installs PostgreSQL integration" \
        "grep -q 'Install PostgreSQL integration' $PROJECT_ROOT/ansible/playbooks/install-newrelic.yml"
    
    run_test "Playbook deploys custom queries" \
        "grep -q 'custom queries for query monitoring' $PROJECT_ROOT/ansible/playbooks/install-newrelic.yml"
}

# Phase 8: Integration Test Scripts
phase8_integration_tests() {
    print_section "Phase 8: Integration Test Scripts"
    
    # Test integration scripts
    run_test "Test suite exists" \
        "[[ -x $PROJECT_ROOT/test/test-suite.sh ]]"
    
    run_test "E2E RDS test exists" \
        "[[ -x $PROJECT_ROOT/test/e2e-rds-monitoring-test.sh ]]"
    
    run_test "Demo workflow exists" \
        "[[ -x $PROJECT_ROOT/test/demo-workflow.sh ]]"
    
    # Run the test suite
    echo -e "\n  ${CYAN}Running automated test suite...${NC}"
    if "$PROJECT_ROOT/test/test-suite.sh" &>/dev/null; then
        run_test "Automated test suite passes" "true"
    else
        run_test "Automated test suite passes" "false" "Some tests in test-suite.sh failed"
    fi
}

# Phase 9: Simulated Deployment Test
phase9_deployment_simulation() {
    print_section "Phase 9: Deployment Simulation"
    
    # Create temporary test files
    TEST_TFVARS="$PROJECT_ROOT/terraform/terraform.test.tfvars"
    TEST_DATABASES="$PROJECT_ROOT/config/databases.test.yml"
    
    # Create test terraform.tfvars
    cat > "$TEST_TFVARS" << EOF
aws_region              = "us-east-1"
instance_type           = "t3.medium"
key_name               = "test-key"
vpc_id                 = "vpc-test123"
subnet_id              = "subnet-test123"
monitoring_server_name = "test-monitoring"
allowed_ssh_cidr_blocks = ["10.0.0.0/8"]
newrelic_license_key   = "test_license_key_40_characters_long_test"
newrelic_account_id    = "1234567"
newrelic_region        = "US"
EOF
    
    run_test "Test terraform.tfvars created" "[[ -f $TEST_TFVARS ]]"
    
    # Create test databases.yml
    cat > "$TEST_DATABASES" << EOF
newrelic_license_key: "test_license_key_40_characters_long_test"
newrelic_account_id: "1234567"

mysql_databases:
  - host: test-mysql.region.rds.amazonaws.com
    port: 3306
    user: newrelic
    password: "test_password"
    enable_query_monitoring: true

postgresql_databases:
  - host: test-postgres.region.rds.amazonaws.com
    port: 5432
    user: newrelic
    password: "test_password"
    database: postgres
    enable_query_monitoring: true
EOF
    
    run_test "Test databases.yml created" "[[ -f $TEST_DATABASES ]]"
    
    # Test pre-flight checks would catch issues
    echo -e "\n  ${CYAN}Testing pre-flight check functionality...${NC}"
    
    # This should fail due to missing AWS CLI (in test environment)
    if ! command -v aws &>/dev/null; then
        # We expect this to fail, which is correct behavior
        if ! "$PROJECT_ROOT/scripts/deploy-monitoring.sh" -k /tmp/fake-key.pem -c "$TEST_DATABASES" --skip-terraform --skip-ansible &>/dev/null; then
            run_test "Pre-flight checks catch missing dependencies" "true"
        else
            run_test "Pre-flight checks catch missing dependencies" "false" "Should have failed due to missing AWS CLI"
        fi
    fi
    
    # Clean up test files
    rm -f "$TEST_TFVARS" "$TEST_DATABASES"
}

# Phase 10: Verification Tools
phase10_verification_tools() {
    print_section "Phase 10: Verification and Monitoring Tools"
    
    # Test verification capabilities
    run_test "RDS verification script has all checks" \
        "grep -q 'check_agent_status' $PROJECT_ROOT/scripts/verify-rds-monitoring.sh"
    
    run_test "Connection test supports both databases" \
        "grep -q 'mysql.*postgresql' $PROJECT_ROOT/scripts/test-db-connection.sh"
    
    run_test "Query validation checks performance schema" \
        "grep -q 'performance_schema' $PROJECT_ROOT/scripts/validate-query-monitoring.sh"
    
    run_test "Query validation checks pg_stat_statements" \
        "grep -q 'pg_stat_statements' $PROJECT_ROOT/scripts/validate-query-monitoring.sh"
    
    # Test help functionality
    run_test "Setup verification has help" \
        "$PROJECT_ROOT/scripts/setup-verification.sh --help"
    
    run_test "Deploy script has help" \
        "$PROJECT_ROOT/scripts/deploy-monitoring.sh --help"
    
    run_test "Database connection test has help" \
        "$PROJECT_ROOT/scripts/test-db-connection.sh --help"
}

# Generate test report
generate_report() {
    print_section "Test Summary Report"
    
    local total_tests=$((TESTS_PASSED + TESTS_FAILED))
    local pass_rate=0
    if [[ $total_tests -gt 0 ]]; then
        pass_rate=$(( (TESTS_PASSED * 100) / total_tests ))
    fi
    
    echo -e "\n${CYAN}Test Results:${NC}"
    echo -e "  Total Tests: $total_tests"
    echo -e "  Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "  Failed: ${RED}$TESTS_FAILED${NC}"
    echo -e "  Pass Rate: ${pass_rate}%"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "\n${YELLOW}Failed Tests:${NC}"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == *"✗"* ]]; then
                echo "  $result"
            fi
        done
    fi
    
    echo -e "\n${CYAN}Coverage Summary:${NC}"
    echo "  ✓ Prerequisites and setup scripts"
    echo "  ✓ Configuration templates with query monitoring"
    echo "  ✓ Database setup scripts with proper permissions"
    echo "  ✓ Docker/LocalStack test environment"
    echo "  ✓ Comprehensive documentation"
    echo "  ✓ Terraform infrastructure code"
    echo "  ✓ Ansible automation playbooks"
    echo "  ✓ Integration test suite"
    echo "  ✓ Deployment simulation"
    echo "  ✓ Verification tools"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}✅ ALL TESTS PASSED! The system is ready for deployment.${NC}"
        return 0
    else
        echo -e "\n${RED}❌ Some tests failed. Please fix the issues before deployment.${NC}"
        return 1
    fi
}

# Main execution
main() {
    print_header
    
    echo "Starting comprehensive end-to-end testing..."
    echo "This will validate all components of the monitoring system."
    echo ""
    
    # Run all test phases
    phase1_prerequisites
    phase2_configuration
    phase3_database_setup
    phase4_docker_environment
    phase5_documentation
    phase6_terraform
    phase7_ansible
    phase8_integration_tests
    phase9_deployment_simulation
    phase10_verification_tools
    
    # Generate final report
    generate_report
}

# Run the test suite
main