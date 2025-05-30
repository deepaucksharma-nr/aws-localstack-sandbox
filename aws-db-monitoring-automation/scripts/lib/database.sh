#!/usr/bin/env bash

# Database utilities for AWS DB monitoring scripts
# This library provides database connection and validation functions

# Source common functions
DATABASE_LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${DATABASE_LIB_DIR}/common.sh"

# Default database ports
export MYSQL_DEFAULT_PORT=3306
export POSTGRESQL_DEFAULT_PORT=5432

# Default monitoring user
export DB_MONITORING_USER="${DB_MONITORING_USER:-newrelic}"

# Check if database port is reachable
check_db_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    print_status "Checking connectivity to $host:$port..."
    
    # Try nc (netcat) first, then fall back to bash tcp check
    if command -v nc &> /dev/null; then
        if nc -z -w "$timeout" "$host" "$port" 2>/dev/null; then
            print_success "Port $port is reachable on $host"
            return 0
        else
            print_error "Cannot reach $host:$port"
            return 1
        fi
    else
        # Fallback to bash tcp check
        if timeout "$timeout" bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
            print_success "Port $port is reachable on $host"
            return 0
        else
            print_error "Cannot reach $host:$port"
            return 1
        fi
    fi
}

# MySQL Connection Test
test_mysql_connection() {
    local host="$1"
    local port="${2:-$MYSQL_DEFAULT_PORT}"
    local user="${3:-$DB_MONITORING_USER}"
    local password="$4"
    local database="${5:-}"
    
    print_status "Testing MySQL connection to $host:$port as user '$user'"
    
    # Test port connectivity first
    if ! check_db_port "$host" "$port"; then
        return 1
    fi
    
    # Build MySQL command
    local mysql_cmd="mysql -h $host -P $port -u $user"
    if [ -n "$password" ]; then
        mysql_cmd="$mysql_cmd -p$password"
    fi
    if [ -n "$database" ]; then
        mysql_cmd="$mysql_cmd -D $database"
    fi
    
    # Test basic connectivity
    if $mysql_cmd -e "SELECT VERSION();" >/dev/null 2>&1; then
        print_success "MySQL connection successful"
    else
        print_error "MySQL connection failed"
        return 1
    fi
    
    return 0
}

# PostgreSQL Connection Test
test_postgresql_connection() {
    local host="$1"
    local port="${2:-$POSTGRESQL_DEFAULT_PORT}"
    local user="${3:-$DB_MONITORING_USER}"
    local password="$4"
    local database="${5:-postgres}"
    
    print_status "Testing PostgreSQL connection to $host:$port as user '$user'"
    
    # Test port connectivity first
    if ! check_db_port "$host" "$port"; then
        return 1
    fi
    
    # Set password via environment variable
    export PGPASSWORD="$password"
    
    # Test basic connectivity
    if psql -h "$host" -p "$port" -U "$user" -d "$database" -c "SELECT VERSION();" >/dev/null 2>&1; then
        print_success "PostgreSQL connection successful"
        unset PGPASSWORD
        return 0
    else
        print_error "PostgreSQL connection failed"
        unset PGPASSWORD
        return 1
    fi
}

# Check MySQL monitoring permissions
check_mysql_monitoring_permissions() {
    local host="$1"
    local port="${2:-$MYSQL_DEFAULT_PORT}"
    local user="${3:-$DB_MONITORING_USER}"
    local password="$4"
    
    print_status "Checking MySQL monitoring permissions for user '$user'"
    
    # Build MySQL command
    local mysql_cmd="mysql -h $host -P $port -u $user"
    if [ -n "$password" ]; then
        mysql_cmd="$mysql_cmd -p$password"
    fi
    
    # Check PROCESS privilege
    print_status "Checking PROCESS privilege..."
    if $mysql_cmd -e "SHOW PROCESSLIST;" >/dev/null 2>&1; then
        print_check_success "PROCESS privilege granted"
    else
        print_check_fail "PROCESS privilege missing"
        print_warning "Grant with: GRANT PROCESS ON *.* TO '$user'@'%';"
        return 1
    fi
    
    # Check performance_schema access
    print_status "Checking performance_schema access..."
    if $mysql_cmd -e "SELECT * FROM performance_schema.threads LIMIT 1;" >/dev/null 2>&1; then
        print_check_success "performance_schema SELECT access granted"
    else
        print_check_fail "performance_schema SELECT access missing"
        print_warning "Grant with: GRANT SELECT ON performance_schema.* TO '$user'@'%';"
        return 1
    fi
    
    # Check if performance_schema is enabled
    print_status "Checking if performance_schema is enabled..."
    local perf_schema_status=$($mysql_cmd -N -e "SELECT @@performance_schema;" 2>/dev/null)
    if [ "$perf_schema_status" == "1" ]; then
        print_check_success "performance_schema is enabled"
    else
        print_check_fail "performance_schema is disabled"
        print_warning "Enable in my.cnf: performance_schema=ON"
        return 1
    fi
    
    return 0
}

# Check PostgreSQL monitoring permissions
check_postgresql_monitoring_permissions() {
    local host="$1"
    local port="${2:-$POSTGRESQL_DEFAULT_PORT}"
    local user="${3:-$DB_MONITORING_USER}"
    local password="$4"
    local database="${5:-postgres}"
    
    print_status "Checking PostgreSQL monitoring permissions for user '$user'"
    
    # Set password via environment variable
    export PGPASSWORD="$password"
    
    # Check pg_stat_statements extension
    print_status "Checking pg_stat_statements extension..."
    local ext_check=$(psql -h "$host" -p "$port" -U "$user" -d "$database" -t -c "SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements';" 2>/dev/null | tr -d ' ')
    
    if [ "$ext_check" == "1" ]; then
        print_check_success "pg_stat_statements extension is installed"
    else
        print_check_fail "pg_stat_statements extension is not installed"
        print_warning "Install with: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
        unset PGPASSWORD
        return 1
    fi
    
    # Check if user can access pg_stat_statements
    print_status "Checking pg_stat_statements access..."
    if psql -h "$host" -p "$port" -U "$user" -d "$database" -c "SELECT COUNT(*) FROM pg_stat_statements;" >/dev/null 2>&1; then
        print_check_success "pg_stat_statements access granted"
    else
        print_check_fail "pg_stat_statements access denied"
        
        # Check PostgreSQL version for appropriate grant
        local pg_version=$(psql -h "$host" -p "$port" -U "$user" -d "$database" -t -c "SELECT split_part(version(), ' ', 2);" 2>/dev/null | tr -d ' ')
        local major_version=$(echo "$pg_version" | cut -d. -f1)
        
        if [ "$major_version" -ge 10 ]; then
            print_warning "Grant with: GRANT pg_read_all_stats TO $user;"
        else
            print_warning "Grant with: GRANT SELECT ON pg_stat_statements TO $user;"
        fi
        unset PGPASSWORD
        return 1
    fi
    
    # Check access to other monitoring views
    print_status "Checking system statistics access..."
    if psql -h "$host" -p "$port" -U "$user" -d "$database" -c "SELECT * FROM pg_stat_user_tables LIMIT 1;" >/dev/null 2>&1; then
        print_check_success "System statistics access granted"
    else
        print_check_fail "System statistics access denied"
        unset PGPASSWORD
        return 1
    fi
    
    unset PGPASSWORD
    return 0
}

# Validate MySQL query monitoring setup
validate_mysql_query_monitoring() {
    local host="$1"
    local port="${2:-$MYSQL_DEFAULT_PORT}"
    local user="${3:-$DB_MONITORING_USER}"
    local password="$4"
    
    print_status "Validating MySQL query monitoring configuration"
    
    # Build MySQL command
    local mysql_cmd="mysql -h $host -P $port -u $user"
    if [ -n "$password" ]; then
        mysql_cmd="$mysql_cmd -p$password"
    fi
    
    # Check statement consumers
    print_status "Checking performance_schema consumers..."
    local consumers=$($mysql_cmd -N -e "SELECT COUNT(*) FROM performance_schema.setup_consumers WHERE name LIKE 'statements%' AND enabled = 'YES';" 2>/dev/null)
    
    if [ "$consumers" -gt 0 ]; then
        print_check_success "Statement consumers are enabled ($consumers active)"
    else
        print_check_fail "No statement consumers are enabled"
        print_warning "Enable with: UPDATE performance_schema.setup_consumers SET enabled = 'YES' WHERE name LIKE 'statements%';"
        return 1
    fi
    
    # Check if events_statements_summary_by_digest is populated
    print_status "Checking query digest collection..."
    local digest_count=$($mysql_cmd -N -e "SELECT COUNT(*) FROM performance_schema.events_statements_summary_by_digest WHERE DIGEST IS NOT NULL;" 2>/dev/null)
    
    if [ "$digest_count" -gt 0 ]; then
        print_check_success "Query digests are being collected ($digest_count found)"
    else
        print_check_warning "No query digests found (database might be idle)"
    fi
    
    return 0
}

# Validate PostgreSQL query monitoring setup
validate_postgresql_query_monitoring() {
    local host="$1"
    local port="${2:-$POSTGRESQL_DEFAULT_PORT}"
    local user="${3:-$DB_MONITORING_USER}"
    local password="$4"
    local database="${5:-postgres}"
    
    print_status "Validating PostgreSQL query monitoring configuration"
    
    # Set password via environment variable
    export PGPASSWORD="$password"
    
    # Check if pg_stat_statements is in shared_preload_libraries
    print_status "Checking shared_preload_libraries..."
    local preload_libs=$(psql -h "$host" -p "$port" -U "$user" -d "$database" -t -c "SHOW shared_preload_libraries;" 2>/dev/null)
    
    if echo "$preload_libs" | grep -q "pg_stat_statements"; then
        print_check_success "pg_stat_statements is in shared_preload_libraries"
    else
        print_check_fail "pg_stat_statements is not in shared_preload_libraries"
        print_warning "Add to postgresql.conf: shared_preload_libraries = 'pg_stat_statements'"
        unset PGPASSWORD
        return 1
    fi
    
    # Check if pg_stat_statements is collecting data
    print_status "Checking statement collection..."
    local stmt_count=$(psql -h "$host" -p "$port" -U "$user" -d "$database" -t -c "SELECT COUNT(*) FROM pg_stat_statements;" 2>/dev/null | tr -d ' ')
    
    if [ "$stmt_count" -gt 0 ]; then
        print_check_success "Statement statistics are being collected ($stmt_count found)"
    else
        print_check_warning "No statement statistics found (database might be idle)"
    fi
    
    # Check pg_stat_statements.track setting
    print_status "Checking pg_stat_statements.track setting..."
    local track_setting=$(psql -h "$host" -p "$port" -U "$user" -d "$database" -t -c "SHOW pg_stat_statements.track;" 2>/dev/null | tr -d ' ')
    
    if [ "$track_setting" == "all" ] || [ "$track_setting" == "top" ]; then
        print_check_success "Statement tracking is enabled (mode: $track_setting)"
    else
        print_check_warning "Statement tracking mode: $track_setting"
    fi
    
    unset PGPASSWORD
    return 0
}

# Execute MySQL query
execute_mysql_query() {
    local host="$1"
    local port="${2:-$MYSQL_DEFAULT_PORT}"
    local user="${3:-$DB_MONITORING_USER}"
    local password="$4"
    local query="$5"
    local database="${6:-}"
    
    # Build MySQL command
    local mysql_cmd="mysql -h $host -P $port -u $user"
    if [ -n "$password" ]; then
        mysql_cmd="$mysql_cmd -p$password"
    fi
    if [ -n "$database" ]; then
        mysql_cmd="$mysql_cmd -D $database"
    fi
    
    $mysql_cmd -e "$query" 2>/dev/null
}

# Execute PostgreSQL query
execute_postgresql_query() {
    local host="$1"
    local port="${2:-$POSTGRESQL_DEFAULT_PORT}"
    local user="${3:-$DB_MONITORING_USER}"
    local password="$4"
    local query="$5"
    local database="${6:-postgres}"
    
    # Set password via environment variable
    export PGPASSWORD="$password"
    
    psql -h "$host" -p "$port" -U "$user" -d "$database" -c "$query" 2>/dev/null
    local result=$?
    
    unset PGPASSWORD
    return $result
}

# Get database version
get_database_version() {
    local db_type="$1"
    local host="$2"
    local port="$3"
    local user="$4"
    local password="$5"
    
    case "$db_type" in
        mysql)
            execute_mysql_query "$host" "$port" "$user" "$password" "SELECT VERSION();" | tail -n1
            ;;
        postgresql|postgres)
            execute_postgresql_query "$host" "$port" "$user" "$password" "SELECT VERSION();" | grep PostgreSQL | head -n1
            ;;
        *)
            print_error "Unknown database type: $db_type"
            return 1
            ;;
    esac
}

# Create monitoring user
create_monitoring_user() {
    local db_type="$1"
    local host="$2"
    local port="$3"
    local admin_user="$4"
    local admin_password="$5"
    local monitoring_user="${6:-$DB_MONITORING_USER}"
    local monitoring_password="$7"
    
    case "$db_type" in
        mysql)
            print_status "Creating MySQL monitoring user: $monitoring_user"
            execute_mysql_query "$host" "$port" "$admin_user" "$admin_password" \
                "CREATE USER IF NOT EXISTS '$monitoring_user'@'%' IDENTIFIED BY '$monitoring_password';"
            execute_mysql_query "$host" "$port" "$admin_user" "$admin_password" \
                "GRANT PROCESS, REPLICATION CLIENT ON *.* TO '$monitoring_user'@'%';"
            execute_mysql_query "$host" "$port" "$admin_user" "$admin_password" \
                "GRANT SELECT ON performance_schema.* TO '$monitoring_user'@'%';"
            execute_mysql_query "$host" "$port" "$admin_user" "$admin_password" \
                "FLUSH PRIVILEGES;"
            ;;
        postgresql|postgres)
            print_status "Creating PostgreSQL monitoring user: $monitoring_user"
            execute_postgresql_query "$host" "$port" "$admin_user" "$admin_password" \
                "CREATE USER $monitoring_user WITH PASSWORD '$monitoring_password';"
            # For PostgreSQL 10+
            execute_postgresql_query "$host" "$port" "$admin_user" "$admin_password" \
                "GRANT pg_read_all_stats TO $monitoring_user;" 2>/dev/null || \
            # For older versions
            execute_postgresql_query "$host" "$port" "$admin_user" "$admin_password" \
                "GRANT SELECT ON pg_stat_statements TO $monitoring_user;"
            ;;
        *)
            print_error "Unknown database type: $db_type"
            return 1
            ;;
    esac
    
    print_success "Monitoring user created successfully"
    return 0
}

# Test database from remote instance
test_db_from_instance() {
    local instance_ip="$1"
    local ssh_key="$2"
    local db_type="$3"
    local db_host="$4"
    local db_port="$5"
    local db_user="$6"
    local db_password="$7"
    
    print_status "Testing $db_type connection from instance $instance_ip to $db_host:$db_port"
    
    # Build remote test command
    local test_cmd
    case "$db_type" in
        mysql)
            test_cmd="mysql -h $db_host -P $db_port -u $db_user -p'$db_password' -e 'SELECT VERSION();'"
            ;;
        postgresql|postgres)
            test_cmd="PGPASSWORD='$db_password' psql -h $db_host -p $db_port -U $db_user -d postgres -c 'SELECT VERSION();'"
            ;;
        *)
            print_error "Unknown database type: $db_type"
            return 1
            ;;
    esac
    
    # Execute test remotely
    if ssh -o StrictHostKeyChecking=no -i "$ssh_key" ec2-user@"$instance_ip" "$test_cmd" >/dev/null 2>&1; then
        print_success "Remote database connection successful"
        return 0
    else
        print_error "Remote database connection failed"
        return 1
    fi
}