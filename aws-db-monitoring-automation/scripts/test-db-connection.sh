#!/bin/bash

set -euo pipefail

# Database Connection Testing Utility

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

Test database connections for New Relic monitoring

OPTIONS:
    --mysql-host HOST       MySQL hostname or IP
    --mysql-port PORT       MySQL port (default: 3306)
    --mysql-user USER       MySQL username (default: newrelic)
    --mysql-pass PASS       MySQL password
    
    --pg-host HOST          PostgreSQL hostname or IP
    --pg-port PORT          PostgreSQL port (default: 5432)
    --pg-user USER          PostgreSQL username (default: newrelic)
    --pg-pass PASS          PostgreSQL password
    --pg-database DB        PostgreSQL database (default: postgres)
    
    --from-instance IP      Test from specific monitoring instance
    --ssh-key PATH          SSH key for monitoring instance
    
    -h, --help              Display this help message

EXAMPLES:
    # Test MySQL connection locally
    $0 --mysql-host mysql.example.com --mysql-pass secretpass

    # Test PostgreSQL from monitoring instance
    $0 --pg-host postgres.example.com --pg-pass secretpass \\
       --from-instance 10.0.1.100 --ssh-key ~/.ssh/key.pem

    # Test both databases
    $0 --mysql-host mysql.example.com --mysql-pass pass1 \\
       --pg-host postgres.example.com --pg-pass pass2
EOF
}

# Default values
MYSQL_PORT="3306"
MYSQL_USER="newrelic"
PG_PORT="5432"
PG_USER="newrelic"
PG_DATABASE="postgres"
FROM_INSTANCE=""
SSH_KEY=""

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

# Function to test MySQL connection
test_mysql_connection() {
    local host="$1"
    local port="$2"
    local user="$3"
    local pass="$4"
    
    print_status "Testing MySQL connection to $host:$port..."
    
    # Test basic connectivity
    if timeout 5 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        print_success "Port $port is reachable on $host"
    else
        print_error "Cannot reach port $port on $host"
        print_warning "Check security groups and network connectivity"
        return 1
    fi
    
    # Test MySQL authentication
    local test_query="SELECT VERSION();"
    local version
    
    if command -v mysql &>/dev/null; then
        version=$(mysql -h "$host" -P "$port" -u "$user" -p"$pass" -sN -e "$test_query" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            print_success "Successfully connected to MySQL"
            print_status "MySQL Version: $version"
            
            # Test monitoring permissions
            print_status "Testing monitoring permissions..."
            
            # Check PROCESS privilege
            local has_process=$(mysql -h "$host" -P "$port" -u "$user" -p"$pass" -sN -e "
                SELECT COUNT(*) FROM information_schema.USER_PRIVILEGES 
                WHERE GRANTEE LIKE '%$user%' AND PRIVILEGE_TYPE = 'PROCESS'" 2>/dev/null)
            
            if [[ "$has_process" == "1" ]]; then
                print_success "User has PROCESS privilege"
            else
                print_error "User lacks PROCESS privilege"
                print_warning "Run: GRANT PROCESS ON *.* TO '$user'@'%';"
            fi
            
            # Check performance_schema access
            local can_access_ps=$(mysql -h "$host" -P "$port" -u "$user" -p"$pass" -sN -e "
                SELECT COUNT(*) FROM performance_schema.setup_consumers LIMIT 1" 2>&1)
            
            if [[ $? -eq 0 ]]; then
                print_success "User can access performance_schema"
            else
                print_error "User cannot access performance_schema"
                print_warning "Run: GRANT SELECT ON performance_schema.* TO '$user'@'%';"
            fi
            
            return 0
        else
            print_error "Failed to connect to MySQL"
            echo "$version" | grep -i "error" | head -n1
            return 1
        fi
    else
        print_warning "mysql client not installed, skipping detailed tests"
        return 0
    fi
}

# Function to test PostgreSQL connection
test_postgresql_connection() {
    local host="$1"
    local port="$2"
    local user="$3"
    local pass="$4"
    local database="$5"
    
    print_status "Testing PostgreSQL connection to $host:$port..."
    
    # Test basic connectivity
    if timeout 5 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        print_success "Port $port is reachable on $host"
    else
        print_error "Cannot reach port $port on $host"
        print_warning "Check security groups and network connectivity"
        return 1
    fi
    
    # Test PostgreSQL authentication
    export PGPASSWORD="$pass"
    
    if command -v psql &>/dev/null; then
        local version=$(psql -h "$host" -p "$port" -U "$user" -d "$database" -tA -c "SELECT VERSION();" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            print_success "Successfully connected to PostgreSQL"
            print_status "PostgreSQL Version: $(echo "$version" | cut -d' ' -f2)"
            
            # Test monitoring permissions
            print_status "Testing monitoring permissions..."
            
            # Check pg_stat_statements
            local has_pgss=$(psql -h "$host" -p "$port" -U "$user" -d "$database" -tA -c "
                SELECT COUNT(*) FROM pg_extension WHERE extname = 'pg_stat_statements'" 2>/dev/null)
            
            if [[ "$has_pgss" == "1" ]]; then
                print_success "pg_stat_statements extension is installed"
                
                # Check access to pg_stat_statements
                if psql -h "$host" -p "$port" -U "$user" -d "$database" -c "SELECT 1 FROM pg_stat_statements LIMIT 1" &>/dev/null; then
                    print_success "User can access pg_stat_statements"
                else
                    print_error "User cannot access pg_stat_statements"
                    print_warning "Run: GRANT pg_read_all_stats TO $user;"
                fi
            else
                print_error "pg_stat_statements extension not installed"
                print_warning "Run: CREATE EXTENSION pg_stat_statements;"
            fi
            
            # Check basic monitoring tables
            if psql -h "$host" -p "$port" -U "$user" -d "$database" -c "SELECT 1 FROM pg_stat_database LIMIT 1" &>/dev/null; then
                print_success "User can access pg_stat_database"
            else
                print_error "User cannot access pg_stat_database"
            fi
            
            unset PGPASSWORD
            return 0
        else
            print_error "Failed to connect to PostgreSQL"
            echo "$version" | grep -i "error\|fatal" | head -n1
            unset PGPASSWORD
            return 1
        fi
    else
        print_warning "psql client not installed, skipping detailed tests"
        unset PGPASSWORD
        return 0
    fi
}

# Function to run tests from monitoring instance
run_from_instance() {
    local instance_ip="$1"
    local ssh_key="$2"
    
    print_status "Connecting to monitoring instance at $instance_ip..."
    
    # Copy this script to the instance
    scp -o StrictHostKeyChecking=no -i "$ssh_key" "$0" "ec2-user@$instance_ip:/tmp/test-db-connection.sh"
    
    # Build command with all parameters
    local remote_cmd="/tmp/test-db-connection.sh"
    
    if [[ -n "${MYSQL_HOST:-}" ]]; then
        remote_cmd="$remote_cmd --mysql-host $MYSQL_HOST --mysql-port $MYSQL_PORT --mysql-user $MYSQL_USER --mysql-pass '$MYSQL_PASS'"
    fi
    
    if [[ -n "${PG_HOST:-}" ]]; then
        remote_cmd="$remote_cmd --pg-host $PG_HOST --pg-port $PG_PORT --pg-user $PG_USER --pg-pass '$PG_PASS' --pg-database $PG_DATABASE"
    fi
    
    # Run tests on the instance
    ssh -o StrictHostKeyChecking=no -i "$ssh_key" "ec2-user@$instance_ip" "$remote_cmd"
    
    # Clean up
    ssh -o StrictHostKeyChecking=no -i "$ssh_key" "ec2-user@$instance_ip" "rm -f /tmp/test-db-connection.sh"
}

# Main execution
main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}         Database Connection Test for New Relic Monitoring      ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
    
    # Check if running from monitoring instance
    if [[ -n "$FROM_INSTANCE" ]]; then
        if [[ -z "$SSH_KEY" ]]; then
            print_error "SSH key required when testing from monitoring instance"
            exit 1
        fi
        
        run_from_instance "$FROM_INSTANCE" "$SSH_KEY"
        exit $?
    fi
    
    # Run local tests
    local tested=false
    local all_passed=true
    
    if [[ -n "${MYSQL_HOST:-}" ]] && [[ -n "${MYSQL_PASS:-}" ]]; then
        test_mysql_connection "$MYSQL_HOST" "$MYSQL_PORT" "$MYSQL_USER" "$MYSQL_PASS" || all_passed=false
        tested=true
        echo ""
    fi
    
    if [[ -n "${PG_HOST:-}" ]] && [[ -n "${PG_PASS:-}" ]]; then
        test_postgresql_connection "$PG_HOST" "$PG_PORT" "$PG_USER" "$PG_PASS" "$PG_DATABASE" || all_passed=false
        tested=true
        echo ""
    fi
    
    if [[ "$tested" == "false" ]]; then
        print_error "No database specified for testing"
        echo ""
        usage
        exit 1
    fi
    
    # Summary
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    if [[ "$all_passed" == "true" ]]; then
        print_success "All connection tests passed!"
    else
        print_error "Some connection tests failed"
        print_warning "Fix the issues above before deploying monitoring"
        exit 1
    fi
}

main