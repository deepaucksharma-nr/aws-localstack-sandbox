#!/bin/bash

# Comprehensive Test Suite for New Relic Database Monitoring

set -uo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test results
PASSED=0
FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local command="$2"
    
    echo -n "Testing $test_name... "
    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}PASSED${NC}"
        ((PASSED++))
    else
        echo -e "${RED}FAILED${NC}"
        ((FAILED++))
    fi
}

echo "=== New Relic Database Monitoring Test Suite ==="
echo

# 1. Check script executability
echo "1. Script Executability Tests"
run_test "setup-verification.sh is executable" "[[ -x scripts/setup-verification.sh ]]"
run_test "deploy-monitoring.sh is executable" "[[ -x scripts/deploy-monitoring.sh ]]"
run_test "test-db-connection.sh is executable" "[[ -x scripts/test-db-connection.sh ]]"
run_test "validate-query-monitoring.sh is executable" "[[ -x scripts/validate-query-monitoring.sh ]]"
echo

# 2. Check required files exist
echo "2. Required Files Tests"
run_test "terraform/main.tf exists" "[[ -f terraform/main.tf ]]"
run_test "terraform/variables.tf exists" "[[ -f terraform/variables.tf ]]"
run_test "ansible/playbooks/install-newrelic.yml exists" "[[ -f ansible/playbooks/install-newrelic.yml ]]"
run_test "MySQL setup script exists" "[[ -f scripts/setup-mysql-monitoring.sql ]]"
run_test "PostgreSQL setup script exists" "[[ -f scripts/setup-postgresql-monitoring.sql ]]"
echo

# 3. Check templates
echo "3. Template Files Tests"
run_test "MySQL config template exists" "[[ -f ansible/templates/mysql-config.yml.j2 ]]"
run_test "PostgreSQL config template exists" "[[ -f ansible/templates/postgresql-config.yml.j2 ]]"
run_test "MySQL custom queries template exists" "[[ -f ansible/templates/mysql-custom-queries.yml.j2 ]]"
run_test "PostgreSQL custom queries template exists" "[[ -f ansible/templates/postgresql-custom-queries.yml.j2 ]]"
echo

# 4. Check query monitoring configuration
echo "4. Query Monitoring Configuration Tests"
run_test "MySQL template has query monitoring" "grep -q 'enable_query_monitoring' ansible/templates/mysql-config.yml.j2"
run_test "PostgreSQL template has pg_stat_statements" "grep -q 'pg_stat_statements' ansible/templates/postgresql-config.yml.j2"
run_test "MySQL custom queries has top queries" "grep -q 'mysql_top_queries_by_time' ansible/templates/mysql-custom-queries.yml.j2"
run_test "PostgreSQL custom queries has top queries" "grep -q 'pg_stat_statements_top_queries_by_time' ansible/templates/postgresql-custom-queries.yml.j2"
echo

# 5. Check documentation
echo "5. Documentation Tests"
run_test "README.md exists" "[[ -f README.md ]]"
run_test "QUICK_START.md exists" "[[ -f QUICK_START.md ]]"
run_test "TROUBLESHOOTING.md exists" "[[ -f docs/TROUBLESHOOTING.md ]]"
run_test "QUERY_MONITORING_GUIDE.md exists" "[[ -f docs/QUERY_MONITORING_GUIDE.md ]]"
echo

# 6. Check configuration examples
echo "6. Configuration Examples Tests"
run_test "terraform.tfvars.example exists" "[[ -f terraform/terraform.tfvars.example ]]"
run_test "databases.example.yml exists" "[[ -f config/databases.example.yml ]]"
run_test "Example has query monitoring enabled" "grep -q 'enable_query_monitoring: true' config/databases.example.yml"
echo

# 7. Check test fixtures
echo "7. Test Fixtures Tests"
run_test "MySQL init SQL exists" "[[ -f test/fixtures/mysql-init.sql ]]"
run_test "PostgreSQL init SQL exists" "[[ -f test/fixtures/postgres-init.sql ]]"
run_test "MySQL init creates newrelic user" "grep -q 'CREATE USER.*newrelic' test/fixtures/mysql-init.sql"
run_test "PostgreSQL init creates newrelic user" "grep -q 'CREATE USER newrelic' test/fixtures/postgres-init.sql"
echo

# 8. Syntax validation
echo "8. Syntax Validation Tests"
run_test "Bash scripts have no syntax errors" "find scripts -name '*.sh' -exec bash -n {} +"
run_test "YAML files are valid" "find . -name '*.yml' -o -name '*.yaml' | grep -v node_modules | xargs -I {} sh -c 'python3 -c \"import yaml; yaml.safe_load(open(\"{}\"))\" 2>/dev/null || true' | wc -l | grep -q 0"
echo

# Summary
echo "=== Test Summary ==="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi