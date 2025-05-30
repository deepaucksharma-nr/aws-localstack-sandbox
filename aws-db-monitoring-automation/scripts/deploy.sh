#!/usr/bin/env bash

# Deploy monitoring infrastructure
# Refactored to use common libraries

set -euo pipefail

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source libraries
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/aws.sh"
source "${LIB_DIR}/validation.sh"

# Default values
ENVIRONMENT="dev"
DRY_RUN=false
SKIP_ANSIBLE=false
AUTO_APPROVE=false
DESTROY=false

# Usage information
usage() {
    cat << EOF
Deploy Monitoring Infrastructure
Part of AWS DB Monitoring Automation

Usage: $(basename "$0") [options]

Options:
    --env ENV           Environment to deploy (dev, staging, prod) [default: dev]
    --dry-run           Run Terraform plan only
    --auto-approve      Skip confirmation prompts
    --skip-ansible      Skip Ansible configuration
    --destroy           Destroy infrastructure
    -h, --help          Show this help message

Examples:
    # Deploy to staging environment
    $(basename "$0") --env staging
    
    # Plan deployment without applying
    $(basename "$0") --env prod --dry-run
    
    # Deploy with auto-approval
    $(basename "$0") --env dev --auto-approve
    
    # Destroy infrastructure
    $(basename "$0") --env dev --destroy

EOF
}

# Run preflight checks
run_preflight_checks() {
    print_status "Running preflight checks..."
    
    # Check prerequisites
    if ! validate_prerequisites terraform ansible aws jq; then
        return 1
    fi
    
    # Validate AWS setup
    if ! validate_aws_setup; then
        return 1
    fi
    
    # Validate Terraform setup
    if ! validate_terraform_setup "1.0.0"; then
        return 1
    fi
    
    # Validate Ansible setup
    if ! validate_ansible_setup; then
        return 1
    fi
    
    # Check configuration files
    if ! validate_config_files "${PROJECT_ROOT}/config"; then
        return 1
    fi
    
    # Check for required files
    local required_files=(
        "terraform/main.tf"
        "terraform/variables.tf"
        "config/databases.yml"
        "ansible/playbooks/install-newrelic.yml"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "${PROJECT_ROOT}/${file}" ]; then
            print_error "Required file not found: ${file}"
            return 1
        fi
    done
    
    print_success "All preflight checks passed"
    return 0
}

# Run Terraform
run_terraform() {
    print_status "Running Terraform..."
    
    cd "${PROJECT_ROOT}/terraform"
    
    # Set environment-specific tfvars file
    local tfvars_file="terraform.${ENVIRONMENT}.tfvars"
    if [ ! -f "$tfvars_file" ]; then
        print_warning "Environment-specific tfvars not found: $tfvars_file"
        print_status "Using default terraform.tfvars"
        tfvars_file="terraform.tfvars"
    fi
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    terraform init -upgrade
    
    # Validate configuration
    print_status "Validating Terraform configuration..."
    terraform validate
    
    if [ "$DESTROY" = true ]; then
        # Destroy infrastructure
        print_warning "Preparing to destroy infrastructure in environment: $ENVIRONMENT"
        
        if [ "$AUTO_APPROVE" = true ]; then
            terraform destroy -var-file="$tfvars_file" -auto-approve
        else
            terraform destroy -var-file="$tfvars_file"
        fi
    elif [ "$DRY_RUN" = true ]; then
        # Plan only
        print_status "Running Terraform plan..."
        terraform plan -var-file="$tfvars_file" -out=tfplan
        
        print_success "Terraform plan complete. Review the plan above."
        print_status "To apply this plan, run without --dry-run"
    else
        # Apply changes
        print_status "Applying Terraform configuration..."
        
        if [ "$AUTO_APPROVE" = true ]; then
            terraform apply -var-file="$tfvars_file" -auto-approve
        else
            terraform apply -var-file="$tfvars_file"
        fi
        
        # Capture outputs
        print_status "Capturing Terraform outputs..."
        terraform output -json > "${PROJECT_ROOT}/terraform-outputs.json"
    fi
    
    cd - >/dev/null
    return 0
}

# Wait for instance to be ready
wait_for_instance() {
    local instance_id="$1"
    local instance_ip="$2"
    
    print_status "Waiting for instance to be ready..."
    
    # Wait for instance to be running
    if ! wait_for_instance_running "$instance_id"; then
        return 1
    fi
    
    # Wait for SSH to be ready
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if validate_ssh_connectivity "$instance_ip" "" "ec2-user" 5; then
            print_success "Instance is ready for configuration"
            return 0
        fi
        
        ((attempt++))
        print_status "Waiting for SSH... (attempt $attempt/$max_attempts)"
        sleep 10
    done
    
    print_error "Instance failed to become SSH accessible"
    return 1
}

# Run Ansible
run_ansible() {
    print_status "Running Ansible configuration..."
    
    # Get Terraform outputs
    if [ ! -f "${PROJECT_ROOT}/terraform-outputs.json" ]; then
        print_error "Terraform outputs not found. Run Terraform first."
        return 1
    fi
    
    # Extract instance information
    local instance_id=$(jq -r '.monitoring_instance_id.value' "${PROJECT_ROOT}/terraform-outputs.json")
    local instance_ip=$(jq -r '.monitoring_instance_public_ip.value' "${PROJECT_ROOT}/terraform-outputs.json")
    local ssh_key_path=$(jq -r '.ssh_private_key_path.value' "${PROJECT_ROOT}/terraform-outputs.json")
    
    if [ "$instance_id" = "null" ] || [ -z "$instance_id" ]; then
        print_error "No monitoring instance found in Terraform outputs"
        return 1
    fi
    
    # Wait for instance
    if ! wait_for_instance "$instance_id" "$instance_ip"; then
        return 1
    fi
    
    # Create dynamic inventory
    print_status "Creating Ansible inventory..."
    cat > "${PROJECT_ROOT}/ansible/inventory/hosts.yml" <<EOF
all:
  hosts:
    monitoring:
      ansible_host: ${instance_ip}
      ansible_user: ec2-user
      ansible_ssh_private_key_file: ${ssh_key_path}
      ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
EOF
    
    # Run Ansible playbook
    cd "${PROJECT_ROOT}/ansible"
    
    print_status "Running Ansible playbook..."
    ansible-playbook \
        -i inventory/hosts.yml \
        playbooks/install-newrelic.yml \
        --extra-vars "@${PROJECT_ROOT}/config/databases.yml"
    
    cd - >/dev/null
    
    print_success "Ansible configuration complete"
    return 0
}

# Generate deployment report
generate_deployment_report() {
    local report_file="${PROJECT_ROOT}/deployment-report-$(get_timestamp).txt"
    
    print_status "Generating deployment report..."
    
    {
        echo "=== AWS DB Monitoring Deployment Report ==="
        echo "Generated: $(get_iso_timestamp)"
        echo "Environment: $ENVIRONMENT"
        echo ""
        
        if [ -f "${PROJECT_ROOT}/terraform-outputs.json" ]; then
            echo "=== Deployed Resources ==="
            echo "Instance ID: $(jq -r '.monitoring_instance_id.value' "${PROJECT_ROOT}/terraform-outputs.json")"
            echo "Instance IP: $(jq -r '.monitoring_instance_public_ip.value' "${PROJECT_ROOT}/terraform-outputs.json")"
            echo "VPC ID: $(jq -r '.vpc_id.value // empty' "${PROJECT_ROOT}/terraform-outputs.json")"
            echo "Region: $(get_aws_region)"
            echo ""
        fi
        
        echo "=== Configuration ==="
        echo "Terraform Version: $(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -n1)"
        echo "Ansible Version: $(ansible --version | head -n1)"
        echo "AWS CLI Version: $(aws --version)"
        echo ""
        
        echo "=== Next Steps ==="
        echo "1. Verify monitoring agent is running:"
        echo "   ssh -i <key-path> ec2-user@<instance-ip> 'sudo systemctl status newrelic-infra'"
        echo ""
        echo "2. Check database connections:"
        echo "   ./pte db test --from-instance <instance-ip> --ssh-key <key-path>"
        echo ""
        echo "3. Validate monitoring setup:"
        echo "   ./pte db validate --from-instance <instance-ip> --ssh-key <key-path>"
        echo ""
        echo "=== End of Report ==="
    } > "$report_file"
    
    print_success "Deployment report saved to: $report_file"
    cat "$report_file"
}

# Main deployment function
deploy() {
    print_status "Starting deployment for environment: $ENVIRONMENT"
    
    # Run preflight checks
    if ! run_preflight_checks; then
        print_error "Preflight checks failed"
        return 1
    fi
    
    # Run Terraform
    if ! run_terraform; then
        print_error "Terraform deployment failed"
        return 1
    fi
    
    # Skip remaining steps if destroying or dry-run
    if [ "$DESTROY" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    # Run Ansible (unless skipped)
    if [ "$SKIP_ANSIBLE" = false ]; then
        if ! run_ansible; then
            print_error "Ansible configuration failed"
            return 1
        fi
    else
        print_warning "Skipping Ansible configuration as requested"
    fi
    
    # Generate report
    generate_deployment_report
    
    print_success "Deployment completed successfully!"
    return 0
}

# Main function
main() {
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --skip-ansible)
                SKIP_ANSIBLE=true
                shift
                ;;
            --destroy)
                DESTROY=true
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
    
    # Validate environment
    case "$ENVIRONMENT" in
        dev|staging|prod)
            ;;
        *)
            print_error "Invalid environment: $ENVIRONMENT"
            print_status "Valid environments: dev, staging, prod"
            exit 1
            ;;
    esac
    
    # Confirm destructive operations
    if [ "$DESTROY" = true ] && [ "$AUTO_APPROVE" = false ]; then
        print_warning "You are about to DESTROY the $ENVIRONMENT environment!"
        read -p "Are you sure? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            print_status "Destruction cancelled"
            exit 0
        fi
    fi
    
    # Run deployment
    deploy
    exit $?
}

# Run main function
main "$@"