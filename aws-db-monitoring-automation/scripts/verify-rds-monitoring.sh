#!/bin/bash

set -euo pipefail

# Verify New Relic RDS Monitoring Setup

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

print_header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}         New Relic RDS Monitoring Verification                  ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_step() {
    echo -e "\n${BLUE}▶ $1${NC}"
    echo -e "${BLUE}────────────────────────────────────────${NC}"
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

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Parse command line arguments
INSTANCE_IP=""
SSH_KEY=""
CONFIG_FILE="${PROJECT_ROOT}/config/databases.yml"
VERBOSE=false

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Verify New Relic Infrastructure agent is collecting RDS data correctly

OPTIONS:
    -i, --instance-ip IP        IP address of monitoring instance
    -k, --ssh-key PATH          Path to SSH key for monitoring instance
    -c, --config PATH           Path to database configuration file
    -v, --verbose               Show detailed output
    -h, --help                  Display this help message

EXAMPLE:
    $0 -i 10.0.1.100 -k ~/.ssh/my-key.pem
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--instance-ip)
            INSTANCE_IP="$2"
            shift 2
            ;;
        -k|--ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
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

# Validate required parameters
if [[ -z "$INSTANCE_IP" ]] || [[ -z "$SSH_KEY" ]]; then
    print_error "Instance IP and SSH key are required"
    usage
    exit 1
fi

# Function to run commands on monitoring instance
run_remote() {
    ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ec2-user@"$INSTANCE_IP" "$@"
}

# Function to check agent status
check_agent_status() {
    print_step "Checking New Relic Infrastructure Agent Status"
    
    # Check if agent is running
    if run_remote "sudo systemctl is-active newrelic-infra" &>/dev/null; then
        print_success "New Relic Infrastructure agent is running"
        
        # Get agent version
        local version=$(run_remote "sudo /usr/bin/newrelic-infra --version 2>/dev/null | head -1" || echo "Unknown")
        print_info "Agent version: $version"
        
        # Check uptime
        local uptime=$(run_remote "sudo systemctl show newrelic-infra --property=ActiveEnterTimestamp" | cut -d= -f2)
        print_info "Running since: $uptime"
    else
        print_error "New Relic Infrastructure agent is NOT running"
        print_warning "Start with: sudo systemctl start newrelic-infra"
        return 1
    fi
}

# Function to verify configuration
verify_configuration() {
    print_step "Verifying Agent Configuration"
    
    # Check main config
    if run_remote "test -f /etc/newrelic-infra.yml" &>/dev/null; then
        print_success "Main configuration file exists"
        
        # Check license key
        if run_remote "sudo grep -q '^license_key:' /etc/newrelic-infra.yml" &>/dev/null; then
            print_success "License key is configured"
        else
            print_error "License key not found in configuration"
        fi
    else
        print_error "Main configuration file missing: /etc/newrelic-infra.yml"
    fi
    
    # Check integration configs
    for db_type in mysql postgresql; do
        if run_remote "test -f /etc/newrelic-infra/integrations.d/${db_type}-config.yml" &>/dev/null; then
            print_success "${db_type^} integration configuration exists"
            
            # Count configured databases
            local count=$(run_remote "sudo grep -c '^\s*-\s*name:' /etc/newrelic-infra/integrations.d/${db_type}-config.yml 2>/dev/null" || echo "0")
            print_info "  Configured ${db_type^} databases: $count"
        else
            print_warning "${db_type^} integration configuration not found"
        fi
    done
}

# Function to test RDS connectivity
test_rds_connectivity() {
    print_step "Testing RDS Database Connectivity"
    
    # Extract RDS endpoints from config
    if [[ -f "$CONFIG_FILE" ]]; then
        # Test MySQL RDS instances
        local mysql_hosts=$(grep -A1 "mysql_databases:" "$CONFIG_FILE" | grep "host:" | awk '{print $3}' | tr -d '"' || true)
        if [[ -n "$mysql_hosts" ]]; then
            echo -e "\n${CYAN}MySQL RDS Instances:${NC}"
            while IFS= read -r host; do
                if [[ -n "$host" ]]; then
                    print_info "Testing connection to MySQL: $host"
                    if run_remote "nc -zv $host 3306" &>/dev/null; then
                        print_success "  Can connect to $host:3306"
                    else
                        print_error "  Cannot connect to $host:3306"
                        print_warning "  Check RDS security groups"
                    fi
                fi
            done <<< "$mysql_hosts"
        fi
        
        # Test PostgreSQL RDS instances
        local pg_hosts=$(grep -A1 "postgresql_databases:" "$CONFIG_FILE" | grep "host:" | awk '{print $3}' | tr -d '"' || true)
        if [[ -n "$pg_hosts" ]]; then
            echo -e "\n${CYAN}PostgreSQL RDS Instances:${NC}"
            while IFS= read -r host; do
                if [[ -n "$host" ]]; then
                    print_info "Testing connection to PostgreSQL: $host"
                    if run_remote "nc -zv $host 5432" &>/dev/null; then
                        print_success "  Can connect to $host:5432"
                    else
                        print_error "  Cannot connect to $host:5432"
                        print_warning "  Check RDS security groups"
                    fi
                fi
            done <<< "$pg_hosts"
        fi
    else
        print_warning "Configuration file not found: $CONFIG_FILE"
    fi
}

# Function to check data collection
check_data_collection() {
    print_step "Checking Data Collection"
    
    # Check recent logs for successful collections
    print_info "Checking recent integration activity..."
    
    # MySQL integration logs
    if run_remote "sudo journalctl -u newrelic-infra --since '5 minutes ago' | grep -i mysql" &>/dev/null; then
        print_success "MySQL integration is active"
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo -e "\n${CYAN}Recent MySQL activity:${NC}"
            run_remote "sudo journalctl -u newrelic-infra --since '5 minutes ago' | grep -i mysql | tail -5"
        fi
    else
        print_warning "No recent MySQL integration activity"
    fi
    
    # PostgreSQL integration logs
    if run_remote "sudo journalctl -u newrelic-infra --since '5 minutes ago' | grep -i postgresql" &>/dev/null; then
        print_success "PostgreSQL integration is active"
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo -e "\n${CYAN}Recent PostgreSQL activity:${NC}"
            run_remote "sudo journalctl -u newrelic-infra --since '5 minutes ago' | grep -i postgresql | tail -5"
        fi
    else
        print_warning "No recent PostgreSQL integration activity"
    fi
    
    # Check for errors
    if run_remote "sudo journalctl -u newrelic-infra --since '10 minutes ago' | grep -iE 'error|failed|cannot connect'" &>/dev/null; then
        print_warning "Found errors in recent logs"
        echo -e "\n${YELLOW}Recent errors:${NC}"
        run_remote "sudo journalctl -u newrelic-infra --since '10 minutes ago' | grep -iE 'error|failed|cannot connect' | tail -10"
    else
        print_success "No errors in recent logs"
    fi
}

# Function to verify data in New Relic
verify_newrelic_data() {
    print_step "Verifying Data in New Relic"
    
    print_info "To verify data is being received in New Relic:"
    echo "  1. Go to: https://one.newrelic.com/infrastructure"
    echo "  2. Look for your monitoring instance hostname"
    echo "  3. Navigate to: Infrastructure > Third-party services"
    echo "  4. Check for MySQL and PostgreSQL integrations"
    echo ""
    echo "  For RDS databases specifically:"
    echo "  - Go to: Infrastructure > AWS > RDS"
    echo "  - Verify your RDS instances appear"
    echo "  - Check the 'Databases' tab for query metrics"
    
    # Test API connectivity
    print_info "\nTesting connectivity to New Relic API..."
    if run_remote "curl -s -I https://infrastructure-api.newrelic.com/" &>/dev/null; then
        print_success "Can reach New Relic API"
    else
        print_error "Cannot reach New Relic API - check outbound HTTPS"
    fi
}

# Function to run manual integration test
manual_integration_test() {
    print_step "Running Manual Integration Test"
    
    print_info "Testing MySQL integration manually..."
    
    # Find the first MySQL host from config
    local mysql_host=$(grep -A5 "mysql_databases:" "$CONFIG_FILE" 2>/dev/null | grep "host:" | head -1 | awk '{print $3}' | tr -d '"' || true)
    
    if [[ -n "$mysql_host" ]]; then
        local mysql_user=$(grep -A5 "mysql_databases:" "$CONFIG_FILE" 2>/dev/null | grep "user:" | head -1 | awk '{print $3}' | tr -d '"' || echo "newrelic")
        
        echo "Running: nri-mysql -hostname $mysql_host -username $mysql_user"
        
        if run_remote "sudo /var/db/newrelic-infra/newrelic-integrations/bin/nri-mysql -hostname $mysql_host -username $mysql_user -password '\$MYSQL_PASSWORD' -verbose 2>&1 | head -20"; then
            print_info "Check the output above for any errors"
        else
            print_error "Manual test failed"
        fi
    else
        print_warning "No MySQL hosts found in configuration"
    fi
}

# Function to generate summary report
generate_summary() {
    print_step "Summary Report"
    
    echo -e "${CYAN}Infrastructure Agent:${NC}"
    run_remote "sudo systemctl status newrelic-infra --no-pager | grep -E 'Active:|Main PID:'" || echo "  Status: Unknown"
    
    echo -e "\n${CYAN}Configured Databases:${NC}"
    run_remote "sudo find /etc/newrelic-infra/integrations.d/ -name '*-config.yml' -exec basename {} \; 2>/dev/null" || echo "  None found"
    
    echo -e "\n${CYAN}Recent Data Points:${NC}"
    local mysql_count=$(run_remote "sudo journalctl -u newrelic-infra --since '1 hour ago' | grep -c 'MysqlSample' 2>/dev/null" || echo "0")
    local pg_count=$(run_remote "sudo journalctl -u newrelic-infra --since '1 hour ago' | grep -c 'PostgresqlSample' 2>/dev/null" || echo "0")
    echo "  MySQL samples in last hour: $mysql_count"
    echo "  PostgreSQL samples in last hour: $pg_count"
    
    echo -e "\n${CYAN}Next Steps:${NC}"
    echo "  1. Fix any connectivity issues identified above"
    echo "  2. Check New Relic UI for your data"
    echo "  3. Set up alerts for critical metrics"
}

# Main execution
main() {
    print_header
    
    # Run all checks
    check_agent_status || true
    verify_configuration || true
    test_rds_connectivity || true
    check_data_collection || true
    verify_newrelic_data || true
    
    if [[ "$VERBOSE" == "true" ]]; then
        manual_integration_test || true
    fi
    
    generate_summary
    
    echo -e "\n${GREEN}Verification complete!${NC}"
}

# Run main function
main