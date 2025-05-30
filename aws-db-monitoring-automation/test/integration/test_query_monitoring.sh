#!/bin/bash

set -euo pipefail

# Test Query Performance Monitoring Setup

echo "Testing Query Performance Monitoring Configuration..."

# Function to run SQL and capture output
run_mysql_test() {
    local query="$1"
    mysql -h mysql -u root -prootpassword -e "$query" 2>/dev/null || echo "FAILED"
}

run_postgres_test() {
    local query="$1"
    PGPASSWORD=rootpassword psql -h postgres -U postgres -d postgres -tA -c "$query" 2>/dev/null || echo "FAILED"
}

# Test MySQL Query Monitoring Setup
echo "=== MySQL Query Monitoring Tests ==="

# Check if performance_schema is enabled
echo -n "Checking performance_schema... "
result=$(run_mysql_test "SELECT @@performance_schema")
if [[ "$result" == "1" ]]; then
    echo "✓ Enabled"
else
    echo "✗ Not enabled"
fi

# Check statement consumers
echo -n "Checking statement consumers... "
result=$(run_mysql_test "SELECT COUNT(*) FROM performance_schema.setup_consumers WHERE NAME LIKE '%statement%' AND ENABLED = 'YES'")
if [[ "$result" -gt 0 ]]; then
    echo "✓ $result consumers enabled"
else
    echo "✗ No statement consumers enabled"
fi

# Check newrelic user permissions
echo -n "Checking newrelic user permissions... "
result=$(run_mysql_test "SELECT COUNT(*) FROM mysql.user WHERE User = 'newrelic'")
if [[ "$result" == "1" ]]; then
    echo "✓ User exists"
else
    echo "✗ User not found"
fi

# Generate some test queries
echo "Generating test queries..."
for i in {1..10}; do
    run_mysql_test "SELECT * FROM information_schema.tables WHERE table_schema = 'mysql' LIMIT $i" >/dev/null
done

# Check if queries are captured
echo -n "Checking captured queries... "
result=$(run_mysql_test "SELECT COUNT(*) FROM performance_schema.events_statements_summary_by_digest")
if [[ "$result" -gt 0 ]]; then
    echo "✓ Found $result query digests"
else
    echo "✗ No queries captured"
fi

echo ""
echo "=== PostgreSQL Query Monitoring Tests ==="

# Check if pg_stat_statements exists
echo -n "Checking pg_stat_statements extension... "
result=$(run_postgres_test "SELECT COUNT(*) FROM pg_extension WHERE extname = 'pg_stat_statements'")
if [[ "$result" == "1" ]]; then
    echo "✓ Installed"
else
    echo "✗ Not installed"
fi

# Check newrelic user
echo -n "Checking newrelic user... "
result=$(run_postgres_test "SELECT COUNT(*) FROM pg_user WHERE usename = 'newrelic'")
if [[ "$result" == "1" ]]; then
    echo "✓ User exists"
else
    echo "✗ User not found"
fi

# Check if user has proper role (PG 10+)
echo -n "Checking pg_read_all_stats role... "
result=$(run_postgres_test "SELECT COUNT(*) FROM pg_roles WHERE pg_has_role('newrelic', oid, 'member') AND rolname = 'pg_read_all_stats'")
if [[ "$result" == "1" ]]; then
    echo "✓ Role granted"
else
    echo "✗ Role not granted"
fi

# Generate some test queries
echo "Generating test queries..."
for i in {1..10}; do
    run_postgres_test "SELECT * FROM pg_stat_database LIMIT $i" >/dev/null
done

# Check if queries are captured
echo -n "Checking captured queries... "
result=$(run_postgres_test "SELECT COUNT(*) FROM pg_stat_statements" 2>/dev/null || echo "0")
if [[ "$result" -gt 0 ]]; then
    echo "✓ Found $result queries"
else
    echo "✗ No queries captured (pg_stat_statements might not be loaded)"
fi

echo ""
echo "=== Integration Configuration Tests ==="

# Check if custom query files would be deployed
echo -n "Checking for custom query templates... "
if [[ -f "/etc/newrelic-infra/integrations.d/mysql-custom-queries.yml" ]]; then
    echo "✓ MySQL custom queries deployed"
else
    echo "✗ MySQL custom queries not found"
fi

if [[ -f "/etc/newrelic-infra/integrations.d/postgresql-custom-queries.yml" ]]; then
    echo "✓ PostgreSQL custom queries deployed"
else
    echo "✗ PostgreSQL custom queries not found"
fi

echo ""
echo "Test completed!"