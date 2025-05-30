#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate Query Performance Monitoring Setup for New Relic

OPTIONS:
    --mysql-host HOST       MySQL host to validate
    --mysql-user USER       MySQL username (default: newrelic)
    --mysql-pass PASS       MySQL password
    --mysql-port PORT       MySQL port (default: 3306)
    
    --pg-host HOST          PostgreSQL host to validate
    --pg-user USER          PostgreSQL username (default: newrelic)
    --pg-pass PASS          PostgreSQL password
    --pg-port PORT          PostgreSQL port (default: 5432)
    --pg-database DB        PostgreSQL database (default: postgres)
    
    -h, --help              Display this help message

EXAMPLES:
    # Validate MySQL setup
    $0 --mysql-host mysql.example.com --mysql-pass secretpass

    # Validate PostgreSQL setup
    $0 --pg-host postgres.example.com --pg-pass secretpass --pg-database mydb

    # Validate both
    $0 --mysql-host mysql.example.com --mysql-pass pass1 \\
       --pg-host postgres.example.com --pg-pass pass2
EOF
}

# Default values
MYSQL_USER="newrelic"
MYSQL_PORT="3306"
PG_USER="newrelic"
PG_PORT="5432"
PG_DATABASE="postgres"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mysql-host)
            MYSQL_HOST="$2"
            shift 2
            ;;
        --mysql-user)
            MYSQL_USER="$2"
            shift 2
            ;;
        --mysql-pass)
            MYSQL_PASS="$2"
            shift 2
            ;;
        --mysql-port)
            MYSQL_PORT="$2"
            shift 2
            ;;
        --pg-host)
            PG_HOST="$2"
            shift 2
            ;;
        --pg-user)
            PG_USER="$2"
            shift 2
            ;;
        --pg-pass)
            PG_PASS="$2"
            shift 2
            ;;
        --pg-port)
            PG_PORT="$2"
            shift 2
            ;;
        --pg-database)
            PG_DATABASE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

validate_mysql() {
    print_status "Validating MySQL Query Performance Monitoring Setup..."
    
    # Test connection
    if ! mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT 1" &>/dev/null; then
        print_error "Cannot connect to MySQL at $MYSQL_HOST:$MYSQL_PORT"
        return 1
    fi
    print_success "Successfully connected to MySQL"
    
    # Check performance_schema
    local perf_schema=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" -sN -e "SELECT @@performance_schema")
    if [[ "$perf_schema" == "1" ]]; then
        print_success "Performance Schema is enabled"
    else
        print_error "Performance Schema is NOT enabled. Query monitoring requires performance_schema=ON"
        print_warning "Add 'performance_schema=ON' to MySQL configuration and restart"
    fi
    
    # Check statement consumers
    local stmt_consumers=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" -sN -e "
        SELECT COUNT(*) FROM performance_schema.setup_consumers 
        WHERE NAME IN ('events_statements_current', 'events_statements_history', 'events_statements_history_long') 
        AND ENABLED = 'YES'")
    
    if [[ "$stmt_consumers" -ge 1 ]]; then
        print_success "Statement consumers are enabled ($stmt_consumers/3)"
    else
        print_error "Statement consumers are NOT properly enabled"
        print_warning "Run: UPDATE performance_schema.setup_consumers SET ENABLED = 'YES' WHERE NAME LIKE '%statement%';"
    fi
    
    # Check permissions
    print_status "Checking user permissions..."
    local has_perf_schema=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" -sN -e "
        SELECT COUNT(*) FROM information_schema.SCHEMA_PRIVILEGES 
        WHERE GRANTEE LIKE '%$MYSQL_USER%' AND TABLE_SCHEMA = 'performance_schema' AND PRIVILEGE_TYPE = 'SELECT'")
    
    if [[ "$has_perf_schema" -ge 1 ]]; then
        print_success "User has SELECT permission on performance_schema"
    else
        print_error "User does NOT have SELECT permission on performance_schema"
        print_warning "Run: GRANT SELECT ON performance_schema.* TO '$MYSQL_USER'@'%';"
    fi
    
    # Check for sample queries
    local query_count=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASS" -sN -e "
        SELECT COUNT(*) FROM performance_schema.events_statements_summary_by_digest WHERE DIGEST IS NOT NULL")
    
    if [[ "$query_count" -gt 0 ]]; then
        print_success "Found $query_count query digests in performance_schema"
    else
        print_warning "No query digests found. This might be normal if the database is idle"
    fi
    
    print_status "MySQL validation complete!"
    echo
}

validate_postgresql() {
    print_status "Validating PostgreSQL Query Performance Monitoring Setup..."
    
    # Set PGPASSWORD for psql
    export PGPASSWORD="$PG_PASS"
    
    # Test connection
    if ! psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -c "SELECT 1" &>/dev/null; then
        print_error "Cannot connect to PostgreSQL at $PG_HOST:$PG_PORT"
        return 1
    fi
    print_success "Successfully connected to PostgreSQL"
    
    # Check pg_stat_statements extension
    local has_extension=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -tA -c "
        SELECT COUNT(*) FROM pg_extension WHERE extname = 'pg_stat_statements'")
    
    if [[ "$has_extension" == "1" ]]; then
        print_success "pg_stat_statements extension is installed"
    else
        print_error "pg_stat_statements extension is NOT installed"
        print_warning "Run: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
        print_warning "May require adding to shared_preload_libraries in postgresql.conf"
    fi
    
    # Check if pg_stat_statements is loaded
    local is_loaded=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -tA -c "
        SELECT COUNT(*) FROM pg_settings WHERE name = 'pg_stat_statements.max' AND setting IS NOT NULL")
    
    if [[ "$is_loaded" == "1" ]]; then
        print_success "pg_stat_statements is loaded"
    else
        print_warning "pg_stat_statements might not be in shared_preload_libraries"
    fi
    
    # Check user permissions (PostgreSQL 10+)
    local pg_version=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -tA -c "SELECT current_setting('server_version_num')::int")
    
    if [[ $pg_version -ge 100000 ]]; then
        local has_role=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -tA -c "
            SELECT COUNT(*) FROM pg_roles WHERE pg_has_role('$PG_USER', oid, 'member') AND rolname = 'pg_read_all_stats'")
        
        if [[ "$has_role" == "1" ]]; then
            print_success "User has pg_read_all_stats role"
        else
            print_error "User does NOT have pg_read_all_stats role"
            print_warning "Run: GRANT pg_read_all_stats TO $PG_USER;"
        fi
    else
        print_warning "PostgreSQL version < 10, checking direct permissions"
        local has_select=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -tA -c "
            SELECT has_table_privilege('$PG_USER', 'pg_stat_statements', 'SELECT')")
        
        if [[ "$has_select" == "t" ]]; then
            print_success "User has SELECT on pg_stat_statements"
        else
            print_error "User does NOT have SELECT on pg_stat_statements"
            print_warning "Run: GRANT SELECT ON pg_stat_statements TO $PG_USER;"
        fi
    fi
    
    # Check for sample queries
    local query_count=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -tA -c "
        SELECT COUNT(*) FROM pg_stat_statements" 2>/dev/null || echo "0")
    
    if [[ "$query_count" -gt 0 ]]; then
        print_success "Found $query_count queries in pg_stat_statements"
    else
        print_warning "No queries found in pg_stat_statements. This might be normal if the database is idle"
    fi
    
    # Check other important tables
    print_status "Checking access to monitoring tables..."
    for table in pg_stat_database pg_stat_user_tables pg_stat_user_indexes; do
        if psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -c "SELECT 1 FROM $table LIMIT 1" &>/dev/null; then
            print_success "Can access $table"
        else
            print_error "Cannot access $table"
        fi
    done
    
    unset PGPASSWORD
    print_status "PostgreSQL validation complete!"
    echo
}

# Main execution
main() {
    print_status "New Relic Query Performance Monitoring Validation Tool"
    echo
    
    local validated=false
    
    if [[ -n "${MYSQL_HOST:-}" ]] && [[ -n "${MYSQL_PASS:-}" ]]; then
        validate_mysql
        validated=true
    fi
    
    if [[ -n "${PG_HOST:-}" ]] && [[ -n "${PG_PASS:-}" ]]; then
        validate_postgresql
        validated=true
    fi
    
    if [[ "$validated" == "false" ]]; then
        print_error "No database specified for validation"
        echo
        usage
        exit 1
    fi
    
    print_success "Validation complete!"
}

# Check for required tools
for tool in mysql psql; do
    if ! command -v $tool &>/dev/null; then
        print_warning "$tool command not found. Install it to validate ${tool%} databases"
    fi
done

main