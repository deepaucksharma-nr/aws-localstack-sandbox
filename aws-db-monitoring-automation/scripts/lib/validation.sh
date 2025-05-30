#!/usr/bin/env bash

# Validation utilities for AWS DB monitoring scripts
# This library provides common validation functions

# Source common functions
VALIDATION_LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${VALIDATION_LIB_DIR}/common.sh"
source "${VALIDATION_LIB_DIR}/aws.sh"

# Validate prerequisites
validate_prerequisites() {
    local required_commands=("$@")
    
    print_status "Validating prerequisites..."
    
    local missing_commands=()
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        print_error "Missing required commands: ${missing_commands[*]}"
        print_warning "Please install the missing commands and try again"
        return 1
    fi
    
    print_success "All prerequisites are installed"
    return 0
}

# Validate AWS setup
validate_aws_setup() {
    print_status "Validating AWS setup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        return 1
    fi
    
    # Check credentials
    if ! check_aws_credentials; then
        print_error "AWS credentials not configured"
        print_warning "Run 'aws configure' to set up credentials"
        return 1
    fi
    
    # Display current identity
    local identity=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
    print_success "AWS identity: $identity"
    
    # Display region
    local region=$(get_aws_region)
    print_success "AWS region: $region"
    
    return 0
}

# Validate Terraform setup
validate_terraform_setup() {
    print_status "Validating Terraform setup..."
    
    # Check Terraform installation
    if ! check_terraform_installed; then
        return 1
    fi
    
    # Check version
    local tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -n1 | cut -d' ' -f2)
    print_success "Terraform version: $tf_version"
    
    # Check for minimum version (optional)
    local min_version="${1:-1.0.0}"
    if [ -n "$min_version" ]; then
        if ! version_ge "$tf_version" "$min_version"; then
            print_warning "Terraform version $tf_version is older than recommended $min_version"
        fi
    fi
    
    return 0
}

# Validate Ansible setup
validate_ansible_setup() {
    print_status "Validating Ansible setup..."
    
    # Check Ansible installation
    if ! command -v ansible &> /dev/null; then
        print_error "Ansible is not installed"
        return 1
    fi
    
    # Check version
    local ansible_version=$(ansible --version | head -n1 | cut -d' ' -f2)
    print_success "Ansible version: $ansible_version"
    
    # Check for ansible-playbook
    if ! command -v ansible-playbook &> /dev/null; then
        print_error "ansible-playbook is not installed"
        return 1
    fi
    
    return 0
}

# Validate Docker setup
validate_docker_setup() {
    print_status "Validating Docker setup..."
    
    # Check Docker installation
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! is_docker_running; then
        return 1
    fi
    
    # Check Docker Compose
    if command -v docker-compose &> /dev/null; then
        local compose_version=$(docker-compose --version | cut -d' ' -f3 | tr -d ',')
        print_success "Docker Compose version: $compose_version"
    elif docker compose version &> /dev/null; then
        local compose_version=$(docker compose version --short)
        print_success "Docker Compose version: $compose_version (plugin)"
    else
        print_warning "Docker Compose is not installed"
    fi
    
    return 0
}

# Validate LocalStack setup
validate_localstack_setup() {
    print_status "Validating LocalStack setup..."
    
    # Check if LocalStack is running
    if ! wait_for_localstack 10; then
        print_warning "LocalStack is not running"
        print_status "Start LocalStack with: docker-compose up -d localstack"
        return 1
    fi
    
    # Initialize LocalStack environment
    init_localstack_env
    
    # Check LocalStack CLI
    if command -v awslocal &> /dev/null; then
        print_success "awslocal CLI is installed"
    else
        print_warning "awslocal CLI not found, using aws with --endpoint-url"
    fi
    
    return 0
}

# Validate configuration files
validate_config_files() {
    local config_dir="${1:-config}"
    
    print_status "Validating configuration files..."
    
    # Check if config directory exists
    if [ ! -d "$config_dir" ]; then
        print_error "Configuration directory not found: $config_dir"
        return 1
    fi
    
    # Validate YAML files
    local yaml_files=("$config_dir"/*.yml "$config_dir"/*.yaml)
    local valid_count=0
    local invalid_count=0
    
    for file in "${yaml_files[@]}"; do
        if [ -f "$file" ]; then
            if validate_yaml "$file"; then
                ((valid_count++))
            else
                ((invalid_count++))
            fi
        fi
    done
    
    # Validate JSON files
    local json_files=("$config_dir"/*.json)
    for file in "${json_files[@]}"; do
        if [ -f "$file" ]; then
            if validate_json "$file"; then
                ((valid_count++))
            else
                ((invalid_count++))
            fi
        fi
    done
    
    if [ $invalid_count -eq 0 ]; then
        print_success "All configuration files are valid ($valid_count files)"
        return 0
    else
        print_error "Found $invalid_count invalid configuration files"
        return 1
    fi
}

# Validate environment variables
validate_environment() {
    local required_vars=("$@")
    
    print_status "Validating environment variables..."
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_error "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    print_success "All required environment variables are set"
    return 0
}

# Validate SSH connectivity
validate_ssh_connectivity() {
    local host="$1"
    local ssh_key="${2:-}"
    local user="${3:-ec2-user}"
    local timeout="${4:-10}"
    
    print_status "Testing SSH connectivity to $host..."
    
    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=$timeout"
    if [ -n "$ssh_key" ]; then
        ssh_opts="$ssh_opts -i $ssh_key"
    fi
    
    if ssh $ssh_opts "$user@$host" "echo 'SSH connection successful'" 2>/dev/null; then
        print_success "SSH connection to $host successful"
        return 0
    else
        print_error "SSH connection to $host failed"
        return 1
    fi
}

# Validate network connectivity
validate_network_connectivity() {
    local targets=("$@")
    
    print_status "Validating network connectivity..."
    
    local failed=0
    for target in "${targets[@]}"; do
        local host="${target%:*}"
        local port="${target#*:}"
        
        if [ "$host" == "$target" ]; then
            # No port specified, use ping
            if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
                print_check_success "$host is reachable"
            else
                print_check_fail "$host is not reachable"
                ((failed++))
            fi
        else
            # Port specified, check TCP connectivity
            if timeout 5 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
                print_check_success "$host:$port is reachable"
            else
                print_check_fail "$host:$port is not reachable"
                ((failed++))
            fi
        fi
    done
    
    if [ $failed -eq 0 ]; then
        print_success "All network targets are reachable"
        return 0
    else
        print_error "$failed network targets are not reachable"
        return 1
    fi
}

# Validate file permissions
validate_file_permissions() {
    local file="$1"
    local expected_perms="${2:-600}"
    
    if [ ! -f "$file" ]; then
        print_error "File not found: $file"
        return 1
    fi
    
    local actual_perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%Lp" "$file" 2>/dev/null)
    
    if [ "$actual_perms" == "$expected_perms" ]; then
        print_success "File permissions are correct: $file ($actual_perms)"
        return 0
    else
        print_warning "File permissions are $actual_perms, expected $expected_perms: $file"
        return 1
    fi
}

# Validate directory structure
validate_directory_structure() {
    local base_dir="${1:-.}"
    shift
    local required_dirs=("$@")
    
    print_status "Validating directory structure..."
    
    local missing_dirs=()
    for dir in "${required_dirs[@]}"; do
        local full_path="$base_dir/$dir"
        if [ ! -d "$full_path" ]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if [ ${#missing_dirs[@]} -eq 0 ]; then
        print_success "All required directories exist"
        return 0
    else
        print_error "Missing directories: ${missing_dirs[*]}"
        return 1
    fi
}

# Validate service health
validate_service_health() {
    local service_name="$1"
    local health_check_cmd="$2"
    local timeout="${3:-30}"
    
    print_status "Validating $service_name health..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$health_check_cmd" >/dev/null 2>&1; then
            print_success "$service_name is healthy"
            return 0
        fi
        sleep 2
        ((elapsed+=2))
    done
    
    print_error "$service_name health check failed after $timeout seconds"
    return 1
}

# Version comparison
version_ge() {
    # Returns 0 if version1 >= version2
    local version1="$1"
    local version2="$2"
    
    # Convert versions to comparable format
    local v1=$(echo "$version1" | awk -F. '{ printf("%d%03d%03d", $1, $2, $3) }')
    local v2=$(echo "$version2" | awk -F. '{ printf("%d%03d%03d", $1, $2, $3) }')
    
    [ "$v1" -ge "$v2" ]
}

# Validate deployment readiness
validate_deployment_readiness() {
    print_status "Validating deployment readiness..."
    
    local all_valid=true
    
    # Check AWS
    if ! validate_aws_setup; then
        all_valid=false
    fi
    
    # Check Terraform
    if ! validate_terraform_setup; then
        all_valid=false
    fi
    
    # Check Ansible
    if ! validate_ansible_setup; then
        all_valid=false
    fi
    
    # Check configuration
    if ! validate_config_files; then
        all_valid=false
    fi
    
    if $all_valid; then
        print_success "System is ready for deployment"
        return 0
    else
        print_error "System is not ready for deployment"
        return 1
    fi
}

# Generate validation report
generate_validation_report() {
    local report_file="${1:-validation-report.txt}"
    
    print_status "Generating validation report..."
    
    {
        echo "=== Validation Report ==="
        echo "Generated: $(date)"
        echo ""
        
        echo "AWS Setup:"
        validate_aws_setup 2>&1 | sed 's/^/  /'
        echo ""
        
        echo "Terraform Setup:"
        validate_terraform_setup 2>&1 | sed 's/^/  /'
        echo ""
        
        echo "Ansible Setup:"
        validate_ansible_setup 2>&1 | sed 's/^/  /'
        echo ""
        
        echo "Docker Setup:"
        validate_docker_setup 2>&1 | sed 's/^/  /'
        echo ""
        
        echo "Configuration Files:"
        validate_config_files 2>&1 | sed 's/^/  /'
        echo ""
        
        echo "=== End of Report ==="
    } > "$report_file"
    
    print_success "Validation report saved to: $report_file"
}