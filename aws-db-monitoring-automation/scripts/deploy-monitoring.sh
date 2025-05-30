#!/usr/bin/env bash
# Enhanced deployment script with race condition fixes

set -euo pipefail

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/aws.sh"
source "$SCRIPT_DIR/lib/validation.sh"

# Configuration
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
CONFIG_DIR="$PROJECT_ROOT/config"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
DRY_RUN="${DRY_RUN:-false}"
MAX_RETRIES="${MAX_RETRIES:-5}"
RETRY_DELAY="${RETRY_DELAY:-10}"

# Help message
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Deploy AWS database monitoring infrastructure with enhanced error handling.

Options:
    -h, --help              Show this help message
    -k, --key PATH          Path to SSH private key
    -a, --auto-approve      Auto-approve Terraform changes
    -d, --dry-run           Show what would be deployed without making changes
    -r, --max-retries NUM   Maximum number of retries (default: 5)
    -w, --retry-delay SEC   Delay between retries in seconds (default: 10)
    -c, --config FILE       Path to configuration file (default: config/databases.yml)

Examples:
    # Standard deployment
    $(basename "$0") -k ~/.ssh/monitoring-key.pem

    # Dry run to see changes
    $(basename "$0") -k ~/.ssh/monitoring-key.pem --dry-run

    # Auto-approve with custom retries
    $(basename "$0") -k ~/.ssh/monitoring-key.pem --auto-approve --max-retries 10

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -k|--key)
                SSH_KEY_PATH="$2"
                shift 2
                ;;
            -a|--auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--max-retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            -w|--retry-delay)
                RETRY_DELAY="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Enhanced retry logic with exponential backoff
retry_with_backoff() {
    local cmd="$1"
    local description="${2:-command}"
    local retries=0
    local delay=$RETRY_DELAY
    
    while [ $retries -lt $MAX_RETRIES ]; do
        print_status "Attempting $description (attempt $((retries+1))/$MAX_RETRIES)..."
        
        if eval "$cmd"; then
            print_success "$description succeeded"
            return 0
        fi
        
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            print_warning "$description failed, retrying in ${delay}s..."
            sleep $delay
            # Exponential backoff with jitter
            delay=$((delay * 2 + RANDOM % 10))
        fi
    done
    
    print_error "$description failed after $MAX_RETRIES attempts"
    return 1
}

# Validate prerequisites with timeout
validate_prerequisites() {
    print_status "Validating prerequisites..."
    
    # Set timeout for validation operations
    local timeout_cmd="timeout 30"
    
    # Check AWS credentials with timeout
    if ! $timeout_cmd aws sts get-caller-identity &>/dev/null; then
        print_error "AWS credentials check failed or timed out"
        return 1
    fi
    print_success "AWS credentials validated"
    
    # Check required tools
    local required_tools=("terraform" "ansible-playbook" "jq" "nc")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            print_error "Required tool not found: $tool"
            return 1
        fi
    done
    print_success "All required tools found"
    
    # Validate SSH key if provided
    if [ -n "$SSH_KEY_PATH" ]; then
        if [ ! -f "$SSH_KEY_PATH" ]; then
            print_error "SSH key not found: $SSH_KEY_PATH"
            return 1
        fi
        
        # Fix permissions if needed
        local perms=$(stat -c "%a" "$SSH_KEY_PATH" 2>/dev/null || stat -f "%Lp" "$SSH_KEY_PATH" 2>/dev/null)
        if [ "$perms" != "600" ]; then
            print_warning "Fixing SSH key permissions..."
            chmod 600 "$SSH_KEY_PATH"
        fi
        print_success "SSH key validated"
    fi
    
    return 0
}

# Run Terraform with proper error handling
run_terraform() {
    cd "$TERRAFORM_DIR"
    
    print_status "Initializing Terraform..."
    if ! terraform init; then
        print_error "Terraform initialization failed"
        return 1
    fi
    
    # Validate configuration
    print_status "Validating Terraform configuration..."
    if ! terraform validate; then
        print_error "Terraform validation failed"
        return 1
    fi
    
    if [ "$DRY_RUN" = true ]; then
        print_status "Running Terraform plan (dry run)..."
        terraform plan -var-file=terraform.tfvars
    else
        print_status "Applying Terraform configuration..."
        if [ "$AUTO_APPROVE" = true ]; then
            terraform apply -var-file=terraform.tfvars -auto-approve
        else
            terraform apply -var-file=terraform.tfvars
        fi
        
        # Wait for outputs to be available
        sleep 2
        
        # Capture outputs with retry
        retry_with_backoff \
            "terraform output -json > '$PROJECT_ROOT/terraform-outputs.json'" \
            "capturing Terraform outputs"
    fi
    
    cd - >/dev/null
}

# Enhanced instance readiness check
wait_for_instance_ready() {
    local instance_ip="$1"
    local ssh_key="$2"
    
    print_status "Waiting for instance to be fully ready..."
    
    # First, check if instance responds to ping
    retry_with_backoff \
        "ping -c 1 -W 2 $instance_ip >/dev/null 2>&1" \
        "ping check to $instance_ip"
    
    # Then check SSH port
    retry_with_backoff \
        "nc -zv -w5 $instance_ip 22 2>&1 | grep -q succeeded" \
        "SSH port check on $instance_ip"
    
    # Finally, check actual SSH connectivity
    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
    if [ -n "$ssh_key" ]; then
        ssh_opts="$ssh_opts -i $ssh_key"
    fi
    
    retry_with_backoff \
        "ssh $ssh_opts ec2-user@$instance_ip 'echo Connection test'" \
        "SSH connection to $instance_ip"
    
    # Give instance a moment to fully initialize
    sleep 5
    
    return 0
}

# Run Ansible with enhanced error handling
run_ansible() {
    print_status "Preparing Ansible deployment..."
    
    # Check for Terraform outputs
    if [ ! -f "$PROJECT_ROOT/terraform-outputs.json" ]; then
        print_error "Terraform outputs not found"
        return 1
    fi
    
    # Extract instance information with validation
    local instance_ip=$(jq -r '.monitoring_instance_public_ip.value // empty' "$PROJECT_ROOT/terraform-outputs.json")
    local instance_id=$(jq -r '.monitoring_instance_id.value // empty' "$PROJECT_ROOT/terraform-outputs.json")
    
    if [ -z "$instance_ip" ] || [ -z "$instance_id" ]; then
        print_error "Failed to extract instance information from Terraform outputs"
        return 1
    fi
    
    print_status "Monitoring instance: $instance_id ($instance_ip)"
    
    # Wait for instance with enhanced checks
    wait_for_instance_ready "$instance_ip" "$SSH_KEY_PATH"
    
    # Create temporary inventory
    local inventory_file="$PROJECT_ROOT/ansible/inventory/hosts.yml"
    print_status "Creating Ansible inventory..."
    cat > "$inventory_file" <<EOF
all:
  hosts:
    monitoring-server:
      ansible_host: $instance_ip
      ansible_user: ec2-user
      ansible_ssh_private_key_file: $SSH_KEY_PATH
      ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
EOF
    
    # Run Ansible playbook with retry
    cd "$ANSIBLE_DIR"
    print_status "Running Ansible playbook..."
    
    local ansible_cmd="ansible-playbook -i inventory/hosts.yml playbooks/install-newrelic.yml"
    
    if retry_with_backoff "$ansible_cmd" "Ansible playbook execution"; then
        print_success "Ansible deployment completed successfully"
    else
        print_error "Ansible deployment failed"
        return 1
    fi
    
    cd - >/dev/null
}

# Main deployment function
deploy() {
    print_status "Starting deployment process..."
    
    # Validate prerequisites
    if ! validate_prerequisites; then
        print_error "Prerequisites validation failed"
        return 1
    fi
    
    # Run Terraform
    if ! run_terraform; then
        print_error "Terraform deployment failed"
        return 1
    fi
    
    if [ "$DRY_RUN" = true ]; then
        print_success "Dry run completed successfully"
        return 0
    fi
    
    # Run Ansible
    if ! run_ansible; then
        print_error "Ansible configuration failed"
        return 1
    fi
    
    print_success "Deployment completed successfully!"
    
    # Display connection information
    local instance_ip=$(jq -r '.monitoring_instance_public_ip.value' "$PROJECT_ROOT/terraform-outputs.json")
    print_status "Monitoring server available at: $instance_ip"
    print_status "SSH: ssh -i $SSH_KEY_PATH ec2-user@$instance_ip"
}

# Cleanup on error
cleanup_on_error() {
    print_error "Deployment failed. Cleaning up..."
    # Add cleanup logic here if needed
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Main execution
main() {
    parse_args "$@"
    deploy
}

# Run main function
main "$@"