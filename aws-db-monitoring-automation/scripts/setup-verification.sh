#!/bin/bash

set -euo pipefail

# Step-by-Step Setup Verification Script for New Relic Database Monitoring

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

# Default values
VERBOSE=false
STEP_BY_STEP=false
FIX_ISSUES=false

# Progress tracking
TOTAL_STEPS=10
CURRENT_STEP=0

print_header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}       New Relic Database Monitoring Setup Verification        ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -e "\n${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS]${NC} $1"
    echo -e "${BLUE}────────────────────────────────────────${NC}"
}

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

print_fix() {
    echo -e "${YELLOW}[FIX]${NC} $1"
}

wait_for_user() {
    if [[ "$STEP_BY_STEP" == "true" ]]; then
        echo -e "\n${YELLOW}Press Enter to continue to the next step...${NC}"
        read -r
    fi
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Step-by-step verification of New Relic database monitoring setup

OPTIONS:
    -v, --verbose           Show detailed output
    -s, --step-by-step      Pause between each step
    -f, --fix               Attempt to fix issues automatically
    -h, --help              Display this help message

EXAMPLES:
    # Basic verification
    $0

    # Step-by-step with fixes
    $0 --step-by-step --fix

    # Verbose output
    $0 --verbose
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -s|--step-by-step)
            STEP_BY_STEP=true
            shift
            ;;
        -f|--fix)
            FIX_ISSUES=true
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

# Step 1: Check Prerequisites
check_prerequisites() {
    print_step "Checking Prerequisites"
    
    local prereqs_met=true
    
    # Check required commands
    local required_commands=("terraform" "ansible-playbook" "aws" "jq" "ssh" "git")
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            print_success "$cmd is installed"
            if [[ "$VERBOSE" == "true" ]]; then
                local version=$($cmd --version 2>&1 | head -n1)
                print_status "  Version: $version"
            fi
        else
            print_error "$cmd is NOT installed"
            prereqs_met=false
            
            case "$cmd" in
                terraform)
                    print_fix "Install Terraform: https://www.terraform.io/downloads"
                    ;;
                ansible-playbook)
                    print_fix "Install Ansible: pip install ansible"
                    ;;
                aws)
                    print_fix "Install AWS CLI: https://aws.amazon.com/cli/"
                    ;;
                jq)
                    print_fix "Install jq: https://stedolan.github.io/jq/download/"
                    ;;
            esac
        fi
    done
    
    # Check AWS credentials
    if aws sts get-caller-identity &>/dev/null; then
        print_success "AWS credentials are configured"
        if [[ "$VERBOSE" == "true" ]]; then
            local identity=$(aws sts get-caller-identity --output json)
            local account=$(echo "$identity" | jq -r '.Account')
            local user=$(echo "$identity" | jq -r '.Arn' | cut -d'/' -f2)
            print_status "  Account: $account"
            print_status "  User/Role: $user"
        fi
    else
        print_error "AWS credentials are NOT configured"
        print_fix "Run: aws configure"
        prereqs_met=false
    fi
    
    if [[ "$prereqs_met" == "false" ]]; then
        print_error "Prerequisites not met. Please install missing components."
        return 1
    fi
    
    wait_for_user
}

# Step 2: Verify Project Structure
verify_project_structure() {
    print_step "Verifying Project Structure"
    
    local required_dirs=(
        "terraform"
        "ansible"
        "ansible/playbooks"
        "ansible/templates"
        "scripts"
        "config"
    )
    
    local required_files=(
        "terraform/main.tf"
        "terraform/variables.tf"
        "terraform/terraform.tfvars.example"
        "ansible/playbooks/install-newrelic.yml"
        "scripts/deploy-monitoring.sh"
        "config/databases.example.yml"
    )
    
    local all_present=true
    
    # Check directories
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$PROJECT_ROOT/$dir" ]]; then
            print_success "Directory exists: $dir"
        else
            print_error "Directory missing: $dir"
            all_present=false
            if [[ "$FIX_ISSUES" == "true" ]]; then
                mkdir -p "$PROJECT_ROOT/$dir"
                print_fix "Created directory: $dir"
            fi
        fi
    done
    
    # Check files
    for file in "${required_files[@]}"; do
        if [[ -f "$PROJECT_ROOT/$file" ]]; then
            print_success "File exists: $file"
        else
            print_error "File missing: $file"
            all_present=false
        fi
    done
    
    if [[ "$all_present" == "false" ]]; then
        print_warning "Some files/directories are missing"
    fi
    
    wait_for_user
}

# Step 3: Check Configuration Files
check_configuration() {
    print_step "Checking Configuration Files"
    
    # Check if terraform.tfvars exists
    if [[ -f "$PROJECT_ROOT/terraform/terraform.tfvars" ]]; then
        print_success "terraform.tfvars exists"
        
        # Check for required variables
        local required_vars=("aws_region" "key_name" "vpc_id" "subnet_id" "newrelic_license_key")
        for var in "${required_vars[@]}"; do
            if grep -q "^$var" "$PROJECT_ROOT/terraform/terraform.tfvars"; then
                print_success "  Variable defined: $var"
            else
                print_error "  Variable missing: $var"
                print_fix "Add $var to terraform/terraform.tfvars"
            fi
        done
    else
        print_error "terraform.tfvars not found"
        if [[ "$FIX_ISSUES" == "true" ]]; then
            cp "$PROJECT_ROOT/terraform/terraform.tfvars.example" "$PROJECT_ROOT/terraform/terraform.tfvars"
            print_fix "Created terraform.tfvars from example"
            print_warning "Please edit terraform/terraform.tfvars with your values"
        else
            print_fix "Copy terraform.tfvars.example to terraform.tfvars and update values"
        fi
    fi
    
    # Check databases.yml
    if [[ -f "$PROJECT_ROOT/config/databases.yml" ]]; then
        print_success "databases.yml exists"
        
        # Check for license key
        if grep -q "YOUR_NEWRELIC_LICENSE_KEY" "$PROJECT_ROOT/config/databases.yml"; then
            print_error "  New Relic license key not configured"
            print_fix "Update newrelic_license_key in config/databases.yml"
        else
            print_success "  New Relic license key configured"
        fi
    else
        print_error "databases.yml not found"
        if [[ "$FIX_ISSUES" == "true" ]]; then
            cp "$PROJECT_ROOT/config/databases.example.yml" "$PROJECT_ROOT/config/databases.yml"
            print_fix "Created databases.yml from example"
            print_warning "Please edit config/databases.yml with your database details"
        else
            print_fix "Copy databases.example.yml to databases.yml and update values"
        fi
    fi
    
    wait_for_user
}

# Step 4: Validate Terraform Configuration
validate_terraform() {
    print_step "Validating Terraform Configuration"
    
    cd "$PROJECT_ROOT/terraform"
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    if terraform init -upgrade &>/dev/null; then
        print_success "Terraform initialized successfully"
    else
        print_error "Terraform initialization failed"
        return 1
    fi
    
    # Validate configuration
    print_status "Validating Terraform configuration..."
    if terraform validate &>/dev/null; then
        print_success "Terraform configuration is valid"
    else
        print_error "Terraform configuration is invalid"
        terraform validate
        return 1
    fi
    
    # Plan (dry run)
    print_status "Running Terraform plan..."
    if terraform plan -out=/tmp/tfplan &>/dev/null; then
        print_success "Terraform plan successful"
        
        # Show resource summary
        if [[ "$VERBOSE" == "true" ]]; then
            print_status "Resources to be created:"
            terraform show -json /tmp/tfplan | jq '.resource_changes[] | select(.change.actions[] == "create") | .address'
        fi
    else
        print_error "Terraform plan failed"
        return 1
    fi
    
    cd "$PROJECT_ROOT"
    wait_for_user
}

# Step 5: Check Database Prerequisites
check_database_prerequisites() {
    print_step "Checking Database Prerequisites"
    
    print_status "Database setup requirements:"
    
    echo -e "\n${CYAN}MySQL Requirements:${NC}"
    print_status "1. MySQL 5.6+ (8.0+ recommended)"
    print_status "2. Performance Schema enabled"
    print_status "3. Monitoring user with proper permissions"
    print_status "4. Network connectivity from monitoring instance"
    
    echo -e "\n${CYAN}PostgreSQL Requirements:${NC}"
    print_status "1. PostgreSQL 9.4+ (10+ recommended)"
    print_status "2. pg_stat_statements extension"
    print_status "3. Monitoring user with pg_read_all_stats role"
    print_status "4. Network connectivity from monitoring instance"
    
    echo -e "\n${YELLOW}Run the following scripts on your databases:${NC}"
    print_status "MySQL: scripts/setup-mysql-monitoring.sql"
    print_status "PostgreSQL: scripts/setup-postgresql-monitoring.sql"
    
    wait_for_user
}

# Step 6: Test SSH Key Access
test_ssh_access() {
    print_step "Testing SSH Key Access"
    
    local key_path=""
    
    # Find SSH key
    if [[ -f "$HOME/.ssh/id_rsa" ]]; then
        key_path="$HOME/.ssh/id_rsa"
    elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
        key_path="$HOME/.ssh/id_ed25519"
    fi
    
    if [[ -n "$key_path" ]]; then
        print_success "Found SSH key: $key_path"
        
        # Check key permissions
        local perms=$(stat -c "%a" "$key_path" 2>/dev/null || stat -f "%A" "$key_path" 2>/dev/null)
        if [[ "$perms" == "600" ]] || [[ "$perms" == "400" ]]; then
            print_success "SSH key has correct permissions"
        else
            print_warning "SSH key permissions should be 600 or 400"
            if [[ "$FIX_ISSUES" == "true" ]]; then
                chmod 600 "$key_path"
                print_fix "Fixed SSH key permissions"
            fi
        fi
    else
        print_error "No SSH key found"
        print_fix "Generate SSH key: ssh-keygen -t rsa -b 4096"
    fi
    
    wait_for_user
}

# Step 7: Check Network Requirements
check_network_requirements() {
    print_step "Checking Network Requirements"
    
    print_status "Required network connectivity:"
    print_status "  - Monitoring instance → Databases (MySQL: 3306, PostgreSQL: 5432)"
    print_status "  - Monitoring instance → New Relic API (HTTPS: 443)"
    print_status "  - Your machine → Monitoring instance (SSH: 22)"
    
    echo -e "\n${CYAN}Security Group Requirements:${NC}"
    print_status "Inbound rules on database security groups:"
    print_status "  - MySQL: TCP 3306 from monitoring instance"
    print_status "  - PostgreSQL: TCP 5432 from monitoring instance"
    
    print_status "Outbound rules on monitoring instance:"
    print_status "  - HTTPS (443) to New Relic endpoints"
    print_status "  - Database ports to your RDS/EC2 instances"
    
    wait_for_user
}

# Step 8: Validate Query Monitoring Setup
validate_query_monitoring() {
    print_step "Validating Query Monitoring Configuration"
    
    # Check for query monitoring files
    local qm_files=(
        "ansible/templates/mysql-custom-queries.yml.j2"
        "ansible/templates/postgresql-custom-queries.yml.j2"
        "scripts/setup-mysql-monitoring.sql"
        "scripts/setup-postgresql-monitoring.sql"
        "scripts/validate-query-monitoring.sh"
    )
    
    for file in "${qm_files[@]}"; do
        if [[ -f "$PROJECT_ROOT/$file" ]]; then
            print_success "Query monitoring file exists: $file"
        else
            print_error "Query monitoring file missing: $file"
        fi
    done
    
    # Check configuration templates
    if grep -q "enable_query_monitoring" "$PROJECT_ROOT/ansible/templates/mysql-config.yml.j2"; then
        print_success "MySQL template includes query monitoring"
    else
        print_error "MySQL template missing query monitoring configuration"
    fi
    
    if grep -q "pg_stat_statements" "$PROJECT_ROOT/ansible/templates/postgresql-config.yml.j2"; then
        print_success "PostgreSQL template includes pg_stat_statements"
    else
        print_error "PostgreSQL template missing pg_stat_statements configuration"
    fi
    
    wait_for_user
}

# Step 9: Pre-deployment Checklist
pre_deployment_checklist() {
    print_step "Pre-deployment Checklist"
    
    echo -e "${CYAN}Before running deployment, ensure:${NC}\n"
    
    local checklist=(
        "terraform.tfvars is configured with your AWS and New Relic credentials"
        "databases.yml contains your database connection details"
        "Database monitoring users are created with proper permissions"
        "Security groups allow connectivity between monitoring instance and databases"
        "SSH key specified in terraform.tfvars exists in AWS"
        "VPC and subnet IDs in terraform.tfvars are valid"
    )
    
    local i=1
    for item in "${checklist[@]}"; do
        echo -e "${YELLOW}$i.${NC} $item"
        i=$((i+1))
    done
    
    echo -e "\n${YELLOW}Ready to deploy?${NC}"
    if [[ "$STEP_BY_STEP" == "true" ]]; then
        read -p "Type 'yes' to confirm readiness: " -r
        if [[ ! "$REPLY" == "yes" ]]; then
            print_warning "Please complete the checklist before deployment"
            return 1
        fi
    fi
    
    wait_for_user
}

# Step 10: Show Next Steps
show_next_steps() {
    print_step "Next Steps"
    
    echo -e "${GREEN}Setup verification complete!${NC}\n"
    
    echo -e "${CYAN}To deploy the monitoring infrastructure:${NC}"
    echo "1. Run the deployment script:"
    echo "   ${YELLOW}./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem${NC}"
    echo ""
    echo "2. After deployment, validate database connections:"
    echo "   ${YELLOW}./scripts/validate-query-monitoring.sh --mysql-host <host> --mysql-pass <pass>${NC}"
    echo "   ${YELLOW}./scripts/validate-query-monitoring.sh --pg-host <host> --pg-pass <pass>${NC}"
    echo ""
    echo "3. Check New Relic for data:"
    echo "   - Infrastructure: ${BLUE}https://one.newrelic.com/infrastructure${NC}"
    echo "   - Databases: ${BLUE}https://one.newrelic.com/infrastructure/databases${NC}"
    echo ""
    echo -e "${CYAN}For troubleshooting:${NC}"
    echo "   - Check logs: ${YELLOW}sudo journalctl -u newrelic-infra -f${NC}"
    echo "   - Run tests: ${YELLOW}make test${NC}"
    echo "   - See docs: ${YELLOW}docs/TROUBLESHOOTING.md${NC}"
}

# Summary function
print_summary() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                         Summary                                ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    
    local total_checks=$((CURRENT_STEP * 5)) # Approximate number of checks
    local passed_checks=$((total_checks - 5)) # Rough estimate
    
    echo -e "\nTotal Steps: ${GREEN}$CURRENT_STEP/$TOTAL_STEPS${NC}"
    echo -e "Status: ${GREEN}Verification Complete${NC}"
    
    if [[ "$FIX_ISSUES" == "true" ]]; then
        echo -e "\n${YELLOW}Some issues were automatically fixed${NC}"
        echo "Please review configuration files before deployment"
    fi
}

# Main execution
main() {
    print_header
    
    # Run all checks
    check_prerequisites || exit 1
    verify_project_structure
    check_configuration
    validate_terraform
    check_database_prerequisites
    test_ssh_access
    check_network_requirements
    validate_query_monitoring
    pre_deployment_checklist
    show_next_steps
    
    print_summary
}

# Run main function
main