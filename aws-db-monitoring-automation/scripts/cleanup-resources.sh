#!/bin/bash
# Comprehensive cleanup script for AWS database monitoring resources

set -euo pipefail

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/aws.sh"

# Configuration
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
FORCE="${FORCE:-false}"
DRY_RUN="${DRY_RUN:-false}"
CLEANUP_LOGS="${CLEANUP_LOGS:-true}"
CLEANUP_TEMP="${CLEANUP_TEMP:-true}"

# Help message
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Clean up AWS database monitoring resources and local artifacts.

Options:
    -h, --help          Show this help message
    -f, --force         Force cleanup without confirmation
    -d, --dry-run       Show what would be cleaned without doing it
    -t, --terraform     Clean up Terraform resources
    -l, --local         Clean up local files only
    -a, --all           Clean up everything (Terraform + local)
    --no-logs           Don't clean up log files
    --no-temp           Don't clean up temporary files

Examples:
    # Clean up everything with confirmation
    $(basename "$0") --all

    # Force cleanup of local files only
    $(basename "$0") --local --force

    # Dry run to see what would be cleaned
    $(basename "$0") --all --dry-run

EOF
}

# Parse command line arguments
parse_args() {
    local cleanup_terraform=false
    local cleanup_local=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -t|--terraform)
                cleanup_terraform=true
                shift
                ;;
            -l|--local)
                cleanup_local=true
                shift
                ;;
            -a|--all)
                cleanup_terraform=true
                cleanup_local=true
                shift
                ;;
            --no-logs)
                CLEANUP_LOGS=false
                shift
                ;;
            --no-temp)
                CLEANUP_TEMP=false
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # If no cleanup option specified, show help
    if [ "$cleanup_terraform" = false ] && [ "$cleanup_local" = false ]; then
        print_error "No cleanup option specified"
        show_help
        exit 1
    fi
    
    CLEANUP_TERRAFORM=$cleanup_terraform
    CLEANUP_LOCAL=$cleanup_local
}

# Confirm cleanup action
confirm_cleanup() {
    if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    print_warning "This will clean up the following:"
    if [ "$CLEANUP_TERRAFORM" = true ]; then
        echo "  - AWS resources created by Terraform"
        echo "  - Terraform state files"
    fi
    if [ "$CLEANUP_LOCAL" = true ]; then
        echo "  - Docker containers and volumes"
        echo "  - Generated configuration files"
        if [ "$CLEANUP_LOGS" = true ]; then
            echo "  - Log files"
        fi
        if [ "$CLEANUP_TEMP" = true ]; then
            echo "  - Temporary files"
        fi
    fi
    
    read -p "Are you sure you want to continue? (yes/no) " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
}

# Clean up Terraform resources
cleanup_terraform() {
    print_step "Cleaning up Terraform resources"
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        print_warning "Terraform directory not found"
        return 0
    fi
    
    cd "$TERRAFORM_DIR"
    
    # Check if Terraform is initialized
    if [ ! -d ".terraform" ]; then
        print_info "Terraform not initialized, skipping"
        cd - >/dev/null
        return 0
    fi
    
    # Check for state file
    if [ ! -f "terraform.tfstate" ]; then
        print_info "No Terraform state found, skipping"
        cd - >/dev/null
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        print_info "Would run: terraform destroy -auto-approve"
        
        # Show resources that would be destroyed
        print_info "Resources that would be destroyed:"
        terraform state list 2>/dev/null || true
    else
        # Destroy resources
        print_status "Destroying Terraform resources..."
        if terraform destroy -auto-approve; then
            print_success "Terraform resources destroyed"
        else
            print_error "Failed to destroy some Terraform resources"
        fi
        
        # Clean up state files
        print_status "Cleaning up Terraform state files..."
        rm -f terraform.tfstate terraform.tfstate.backup
        rm -rf .terraform
        rm -f .terraform.lock.hcl
        rm -f tfplan *.tfplan
        
        print_success "Terraform cleanup complete"
    fi
    
    cd - >/dev/null
}

# Clean up Docker resources
cleanup_docker() {
    print_step "Cleaning up Docker resources"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "Would stop and remove Docker containers:"
        docker-compose ps 2>/dev/null || true
        
        print_info "Would remove Docker volumes:"
        docker volume ls -q | grep -E "(mysql|postgres|localstack)_data" || true
    else
        # Stop and remove containers
        print_status "Stopping Docker containers..."
        docker-compose down -v 2>/dev/null || true
        
        # Remove specific containers if they exist
        for container in localstack mysql-test postgres-test newrelic-mock test-runner; do
            if docker ps -a | grep -q "$container"; then
                docker rm -f "$container" 2>/dev/null || true
            fi
        done
        
        # Clean up volumes
        print_status "Removing Docker volumes..."
        docker volume ls -q | grep -E "(mysql|postgres|localstack)_data" | xargs -r docker volume rm 2>/dev/null || true
        
        # Clean up networks
        docker network ls -q | grep monitoring | xargs -r docker network rm 2>/dev/null || true
        
        print_success "Docker cleanup complete"
    fi
}

# Clean up local files
cleanup_local_files() {
    print_step "Cleaning up local files"
    
    # Configuration files
    print_status "Cleaning up configuration files..."
    local config_files=(
        "$PROJECT_ROOT/ansible/inventory/hosts.yml"
        "$PROJECT_ROOT/config/databases.yml"
        "$PROJECT_ROOT/terraform-outputs.json"
        "$PROJECT_ROOT/.env"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            if [ "$DRY_RUN" = true ]; then
                print_info "Would remove: $file"
            else
                rm -f "$file"
                print_check_success "Removed $file"
            fi
        fi
    done
    
    # Temporary files
    if [ "$CLEANUP_TEMP" = true ]; then
        print_status "Cleaning up temporary files..."
        if [ "$DRY_RUN" = true ]; then
            print_info "Would remove temporary files in /tmp/test-*"
            find /tmp -name "test-*" -type f 2>/dev/null || true
        else
            find /tmp -name "test-*" -type f -exec rm -f {} \; 2>/dev/null || true
            find "$PROJECT_ROOT" -name "*.tmp" -type f -exec rm -f {} \; 2>/dev/null || true
            find "$PROJECT_ROOT" -name "*.bak" -type f -exec rm -f {} \; 2>/dev/null || true
            print_check_success "Removed temporary files"
        fi
    fi
    
    # Log files
    if [ "$CLEANUP_LOGS" = true ]; then
        print_status "Cleaning up log files..."
        if [ "$DRY_RUN" = true ]; then
            print_info "Would remove log files"
            find "$PROJECT_ROOT" -name "*.log" -type f 2>/dev/null || true
        else
            find "$PROJECT_ROOT" -name "*.log" -type f -exec rm -f {} \; 2>/dev/null || true
            rm -rf "$PROJECT_ROOT/test/results" 2>/dev/null || true
            rm -rf "$PROJECT_ROOT/.localstack" 2>/dev/null || true
            print_check_success "Removed log files"
        fi
    fi
    
    # Python cache
    print_status "Cleaning up Python cache..."
    if [ "$DRY_RUN" = true ]; then
        print_info "Would remove Python cache directories"
    else
        find "$PROJECT_ROOT" -type d -name "__pycache__" -exec rm -rf {} \; 2>/dev/null || true
        find "$PROJECT_ROOT" -name "*.pyc" -type f -exec rm -f {} \; 2>/dev/null || true
        print_check_success "Removed Python cache"
    fi
    
    # Secrets directory
    if [ -d "$PROJECT_ROOT/secrets" ]; then
        print_warning "Found secrets directory. Remove manually if needed: $PROJECT_ROOT/secrets"
    fi
}

# Clean up AWS resources (for stuck resources)
cleanup_aws_resources() {
    print_step "Checking for orphaned AWS resources"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "Would check for orphaned AWS resources"
        return 0
    fi
    
    # This function can be extended to clean up specific AWS resources
    # that might be left behind due to failed Terraform runs
    
    print_info "Manual cleanup may be required for:"
    echo "  - IAM roles and policies"
    echo "  - Security groups"
    echo "  - EC2 instances"
    echo "  - Secrets in AWS Secrets Manager"
    echo "  - SSM parameters"
}

# Main cleanup function
cleanup() {
    print_status "Starting cleanup process..."
    
    if [ "$CLEANUP_TERRAFORM" = true ]; then
        cleanup_terraform
    fi
    
    if [ "$CLEANUP_LOCAL" = true ]; then
        cleanup_docker
        cleanup_local_files
    fi
    
    # Always check for orphaned resources
    if [ "$CLEANUP_TERRAFORM" = true ] && [ "$DRY_RUN" = false ]; then
        cleanup_aws_resources
    fi
    
    if [ "$DRY_RUN" = true ]; then
        print_success "Dry run completed. No changes were made."
    else
        print_success "Cleanup completed successfully!"
    fi
}

# Main execution
main() {
    parse_args "$@"
    confirm_cleanup
    cleanup
}

# Run main function
main "$@"