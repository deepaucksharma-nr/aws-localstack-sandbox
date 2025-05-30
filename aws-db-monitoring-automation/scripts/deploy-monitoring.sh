#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
CONFIG_FILE="${PROJECT_ROOT}/config/databases.yml"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/hosts.yml"
SSH_KEY_PATH=""
SKIP_TERRAFORM=false
SKIP_ANSIBLE=false

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

New Relic Database Monitoring AWS Deployment Script

OPTIONS:
    -k, --ssh-key PATH          Path to SSH private key for instance access
    -c, --config PATH           Path to database configuration file (default: config/databases.yml)
    -i, --inventory PATH        Path to Ansible inventory file (default: ansible/inventory/hosts.yml)
    --skip-terraform            Skip Terraform deployment (use existing instance)
    --skip-ansible              Skip Ansible configuration
    -h, --help                  Display this help message

EXAMPLES:
    # Full deployment
    $0 -k ~/.ssh/my-key.pem

    # Only run Ansible on existing instance
    $0 -k ~/.ssh/my-key.pem --skip-terraform

    # Custom configuration file
    $0 -k ~/.ssh/my-key.pem -c /path/to/custom-databases.yml
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--ssh-key)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -i|--inventory)
            INVENTORY_FILE="$2"
            shift 2
            ;;
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --skip-ansible)
            SKIP_ANSIBLE=true
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
if [[ -z "$SSH_KEY_PATH" ]] && [[ "$SKIP_ANSIBLE" == "false" ]]; then
    print_error "SSH key path is required unless using --skip-ansible"
    usage
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]] && [[ "$SKIP_ANSIBLE" == "false" ]]; then
    print_error "Database configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Function to run pre-flight checks
run_preflight_checks() {
    print_status "Running pre-flight checks..."
    
    local checks_passed=true
    
    # Check Terraform
    if command -v terraform &>/dev/null; then
        print_success "Terraform is installed"
    else
        print_error "Terraform is not installed"
        checks_passed=false
    fi
    
    # Check Ansible
    if command -v ansible-playbook &>/dev/null; then
        print_success "Ansible is installed"
    else
        print_error "Ansible is not installed"
        checks_passed=false
    fi
    
    # Check AWS CLI
    if command -v aws &>/dev/null; then
        print_success "AWS CLI is installed"
        
        # Check AWS credentials
        if aws sts get-caller-identity &>/dev/null; then
            print_success "AWS credentials are configured"
        else
            print_error "AWS credentials are not configured"
            print_error "Run: aws configure"
            checks_passed=false
        fi
    else
        print_error "AWS CLI is not installed"
        checks_passed=false
    fi
    
    # Check SSH key
    if [[ "$SKIP_ANSIBLE" == "false" ]] && [[ -n "$SSH_KEY_PATH" ]]; then
        if [[ -f "$SSH_KEY_PATH" ]]; then
            print_success "SSH key exists: $SSH_KEY_PATH"
            
            # Check permissions
            local perms=$(stat -c "%a" "$SSH_KEY_PATH" 2>/dev/null || stat -f "%A" "$SSH_KEY_PATH" 2>/dev/null)
            if [[ "$perms" == "600" ]] || [[ "$perms" == "400" ]]; then
                print_success "SSH key has correct permissions"
            else
                print_warning "SSH key permissions should be 600 or 400"
                print_status "Fixing permissions..."
                chmod 600 "$SSH_KEY_PATH"
            fi
        else
            print_error "SSH key not found: $SSH_KEY_PATH"
            checks_passed=false
        fi
    fi
    
    # Check configuration files
    if [[ "$SKIP_TERRAFORM" == "false" ]]; then
        if [[ -f "$TERRAFORM_DIR/terraform.tfvars" ]]; then
            print_success "terraform.tfvars exists"
            
            # Check for placeholder values
            if grep -q "YOUR_" "$TERRAFORM_DIR/terraform.tfvars"; then
                print_error "terraform.tfvars contains placeholder values"
                print_error "Please update all YOUR_* values in terraform.tfvars"
                checks_passed=false
            fi
        else
            print_error "terraform.tfvars not found"
            print_error "Copy terraform.tfvars.example to terraform.tfvars and update values"
            checks_passed=false
        fi
    fi
    
    if [[ "$SKIP_ANSIBLE" == "false" ]]; then
        if grep -q "YOUR_NEWRELIC_LICENSE_KEY" "$CONFIG_FILE" 2>/dev/null; then
            print_error "Database configuration contains placeholder license key"
            print_error "Please update newrelic_license_key in $CONFIG_FILE"
            checks_passed=false
        fi
    fi
    
    if [[ "$checks_passed" == "false" ]]; then
        print_error "Pre-flight checks failed. Please fix the issues above and try again."
        exit 1
    fi
    
    print_success "All pre-flight checks passed!"
}

# Function to run Terraform
run_terraform() {
    print_status "Starting Terraform deployment..."
    
    cd "$TERRAFORM_DIR"
    
    # Check if terraform.tfvars exists
    if [[ ! -f "terraform.tfvars" ]]; then
        print_error "terraform.tfvars not found. Please copy terraform.tfvars.example and update with your values."
        exit 1
    fi
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    terraform init
    
    # Plan deployment
    print_status "Planning Terraform deployment..."
    terraform plan -out=tfplan
    
    # Apply deployment
    print_status "Applying Terraform configuration..."
    terraform apply tfplan
    
    # Get outputs
    INSTANCE_IP=$(terraform output -raw instance_public_ip)
    INSTANCE_ID=$(terraform output -raw instance_id)
    
    print_success "EC2 instance created successfully!"
    print_status "Instance ID: $INSTANCE_ID"
    print_status "Instance IP: $INSTANCE_IP"
    
    # Generate Ansible inventory
    print_status "Generating Ansible inventory..."
    cat > "$INVENTORY_FILE" << EOF
all:
  hosts:
    monitoring_server:
      ansible_host: $INSTANCE_IP
      ansible_user: ec2-user
      ansible_ssh_private_key_file: $SSH_KEY_PATH
      ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
EOF
    
    cd "$PROJECT_ROOT"
}

# Function to wait for instance to be ready
wait_for_instance() {
    print_status "Waiting for instance to be ready..."
    
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -i "$SSH_KEY_PATH" ec2-user@"$INSTANCE_IP" "echo 'Instance ready'" &>/dev/null; then
            print_success "Instance is ready for configuration!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        print_status "Waiting for SSH access... (attempt $attempt/$max_attempts)"
        sleep 10
    done
    
    print_error "Timeout waiting for instance to be ready"
    return 1
}

# Function to run Ansible
run_ansible() {
    print_status "Starting Ansible configuration..."
    
    cd "$ANSIBLE_DIR"
    
    # Check if inventory exists
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        print_error "Ansible inventory file not found: $INVENTORY_FILE"
        print_error "If using --skip-terraform, please create the inventory file manually"
        exit 1
    fi
    
    # Get instance IP from inventory if not set
    if [[ -z "${INSTANCE_IP:-}" ]]; then
        INSTANCE_IP=$(grep ansible_host "$INVENTORY_FILE" | awk '{print $2}')
    fi
    
    # Wait for instance
    wait_for_instance
    
    # Run Ansible playbook
    print_status "Running Ansible playbook to install New Relic Infrastructure agent..."
    ansible-playbook \
        -i "$INVENTORY_FILE" \
        playbooks/install-newrelic.yml \
        -e "@$CONFIG_FILE"
    
    print_success "New Relic Infrastructure agent installed and configured!"
    
    # Display verification commands
    print_status "To verify the installation, SSH to the instance and run:"
    print_status "  sudo systemctl status newrelic-infra"
    print_status "  sudo cat /etc/newrelic-infra/integrations.d/mysql-config.yml"
    print_status "  sudo cat /etc/newrelic-infra/integrations.d/postgresql-config.yml"
    
    cd "$PROJECT_ROOT"
}

# Function to display next steps
display_next_steps() {
    print_success "Deployment completed successfully!"
    
    if [[ "$SKIP_TERRAFORM" == "false" ]] && [[ "$SKIP_ANSIBLE" == "false" ]]; then
        print_status ""
        print_status "Next steps:"
        print_status "1. SSH to the monitoring server:"
        print_status "   ssh -i $SSH_KEY_PATH ec2-user@$INSTANCE_IP"
        print_status ""
        print_status "2. Check New Relic Infrastructure agent status:"
        print_status "   sudo systemctl status newrelic-infra"
        print_status ""
        print_status "3. View your infrastructure in New Relic One:"
        print_status "   https://one.newrelic.com/infrastructure"
        print_status ""
        print_status "4. View database monitoring:"
        print_status "   https://one.newrelic.com/infrastructure/databases"
    fi
}

# Main execution
main() {
    print_status "Starting New Relic Database Monitoring Deployment"
    print_status "Configuration file: $CONFIG_FILE"
    
    # Run pre-flight checks
    run_preflight_checks
    
    # Run Terraform unless skipped
    if [[ "$SKIP_TERRAFORM" == "false" ]]; then
        run_terraform
    else
        print_warning "Skipping Terraform deployment"
    fi
    
    # Run Ansible unless skipped
    if [[ "$SKIP_ANSIBLE" == "false" ]]; then
        run_ansible
    else
        print_warning "Skipping Ansible configuration"
    fi
    
    display_next_steps
}

# Run main function
main