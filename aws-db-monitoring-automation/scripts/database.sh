#!/usr/bin/env bash
# Unified Database Operations Script
# Consolidates all database testing and monitoring functionality

set -euo pipefail

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/database.sh"

# Show help
show_help() {
    cat << EOF
Database Operations Script
Part of AWS DB Monitoring Automation

Usage: $(basename "$0") <command> [options]

Commands:
    test            Test database connections
    validate        Validate monitoring setup
    full            Run all tests (default)
    create-user     Create monitoring user

Options:
    MySQL Options:
        --mysql-host HOST       MySQL host
        --mysql-port PORT       MySQL port (default: 3306)
        --mysql-user USER       MySQL user (default: newrelic)
        --mysql-pass PASS       MySQL password

    PostgreSQL Options:
        --pg-host HOST          PostgreSQL host
        --pg-port PORT          PostgreSQL port (default: 5432)
        --pg-user USER          PostgreSQL user (default: newrelic)
        --pg-pass PASS          PostgreSQL password
        --pg-database DB        PostgreSQL database (default: postgres)

    Remote Execution:
        --from-instance IP      Run tests from monitoring instance
        --ssh-key PATH          SSH key for instance access

Examples:
    # Test MySQL connection
    $(basename "$0") test --mysql-host db.example.com --mysql-pass secret

    # Validate PostgreSQL monitoring
    $(basename "$0") validate --pg-host postgres.example.com --pg-pass secret

    # Run all tests from monitoring instance
    $(basename "$0") full --from-instance 10.0.1.100 --ssh-key ~/.ssh/id_rsa

    # Create monitoring user
    $(basename "$0") create-user --mysql-host db.example.com --admin-user root --admin-pass admin123
EOF
}

# Parse command line arguments
COMMAND="${1:-full}"
shift || true

# MySQL settings
MYSQL_HOST=""
MYSQL_PORT="3306"
MYSQL_USER="newrelic"
MYSQL_PASS=""

# PostgreSQL settings
PG_HOST=""
PG_PORT="5432"
PG_USER="newrelic"
PG_PASS=""
PG_DATABASE="postgres"

# Remote execution settings
FROM_INSTANCE=""
SSH_KEY=""

# Admin credentials for user creation
ADMIN_USER=""
ADMIN_PASS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mysql-host)
            MYSQL_HOST="$2"
            shift 2
            ;;
        --mysql-port)
            MYSQL_PORT="$2"
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
        --pg-host)
            PG_HOST="$2"
            shift 2
            ;;
        --pg-port)
            PG_PORT="$2"
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
        --pg-database)
            PG_DATABASE="$2"
            shift 2
            ;;
        --from-instance)
            FROM_INSTANCE="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        --admin-user)
            ADMIN_USER="$2"
            shift 2
            ;;
        --admin-pass)
            ADMIN_PASS="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute command
case "$COMMAND" in
    test)
        print_status "Running database connection tests..."
        
        if [ -n "$MYSQL_HOST" ]; then
            test_mysql_connection "$MYSQL_HOST" "$MYSQL_PORT" "$MYSQL_USER" "$MYSQL_PASS"
        fi
        
        if [ -n "$PG_HOST" ]; then
            test_postgresql_connection "$PG_HOST" "$PG_PORT" "$PG_USER" "$PG_PASS" "$PG_DATABASE"
        fi
        
        if [ -z "$MYSQL_HOST" ] && [ -z "$PG_HOST" ]; then
            print_error "No database host specified"
            exit 1
        fi
        ;;
        
    validate)
        print_status "Validating database monitoring setup..."
        
        if [ -n "$MYSQL_HOST" ]; then
            validate_mysql_monitoring "$MYSQL_HOST" "$MYSQL_PORT" "$MYSQL_USER" "$MYSQL_PASS"
        fi
        
        if [ -n "$PG_HOST" ]; then
            validate_postgresql_monitoring "$PG_HOST" "$PG_PORT" "$PG_USER" "$PG_PASS" "$PG_DATABASE"
        fi
        
        if [ -z "$MYSQL_HOST" ] && [ -z "$PG_HOST" ]; then
            print_error "No database host specified"
            exit 1
        fi
        ;;
        
    create-user)
        print_status "Creating monitoring users..."
        
        if [ -n "$MYSQL_HOST" ]; then
            create_mysql_monitoring_user "$MYSQL_HOST" "$MYSQL_PORT" "$ADMIN_USER" "$ADMIN_PASS" "$MYSQL_USER" "$MYSQL_PASS"
        fi
        
        if [ -n "$PG_HOST" ]; then
            create_postgresql_monitoring_user "$PG_HOST" "$PG_PORT" "$ADMIN_USER" "$ADMIN_PASS" "$PG_USER" "$PG_PASS"
        fi
        ;;
        
    full|*)
        print_status "Running full database tests..."
        
        # Run all tests if hosts are specified
        if [ -n "$MYSQL_HOST" ]; then
            print_status "Testing MySQL..."
            test_mysql_connection "$MYSQL_HOST" "$MYSQL_PORT" "$MYSQL_USER" "$MYSQL_PASS" || true
            validate_mysql_monitoring "$MYSQL_HOST" "$MYSQL_PORT" "$MYSQL_USER" "$MYSQL_PASS" || true
        fi
        
        if [ -n "$PG_HOST" ]; then
            print_status "Testing PostgreSQL..."
            test_postgresql_connection "$PG_HOST" "$PG_PORT" "$PG_USER" "$PG_PASS" "$PG_DATABASE" || true
            validate_postgresql_monitoring "$PG_HOST" "$PG_PORT" "$PG_USER" "$PG_PASS" "$PG_DATABASE" || true
        fi
        
        if [ -z "$MYSQL_HOST" ] && [ -z "$PG_HOST" ]; then
            print_warning "No database hosts specified, showing help"
            show_help
        fi
        ;;
esac