#!/bin/bash
# Lifecycle management script for database monitoring infrastructure

set -euo pipefail

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/aws.sh"

# Configuration
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
MAX_BACKUP_SIZE="${MAX_BACKUP_SIZE:-1G}"

# Help message
show_help() {
    cat << EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Lifecycle management for database monitoring infrastructure.

Commands:
    backup              Create backup of configuration and state
    restore             Restore from backup
    rotate              Rotate old backups and logs
    status              Show current status
    health-check        Perform health check of all components

Options:
    -h, --help          Show this help message
    -b, --backup-dir    Backup directory (default: $BACKUP_DIR)
    -r, --retention     Backup retention in days (default: $RETENTION_DAYS)
    -l, --log-retention Log retention in days (default: $LOG_RETENTION_DAYS)
    -f, --file          Specific backup file for restore

Examples:
    # Create a backup
    $(basename "$0") backup

    # Restore from specific backup
    $(basename "$0") restore --file backups/backup-20240101-120000.tar.gz

    # Rotate old backups
    $(basename "$0") rotate --retention 14

    # Check system health
    $(basename "$0") health-check

EOF
}

# Create backup
create_backup() {
    print_step "Creating backup"
    
    # Create backup directory
    ensure_directory "$BACKUP_DIR"
    
    # Generate backup filename
    local timestamp=$(get_timestamp)
    local backup_file="$BACKUP_DIR/backup-${timestamp}.tar.gz"
    local temp_dir="/tmp/backup-${timestamp}"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    
    # Collect files to backup
    print_status "Collecting configuration files..."
    
    # Terraform state and configuration
    if [ -d "$TERRAFORM_DIR" ]; then
        mkdir -p "$temp_dir/terraform"
        cp -r "$TERRAFORM_DIR"/*.tf "$temp_dir/terraform/" 2>/dev/null || true
        cp -r "$TERRAFORM_DIR"/*.tfvars "$temp_dir/terraform/" 2>/dev/null || true
        cp "$TERRAFORM_DIR"/terraform.tfstate* "$temp_dir/terraform/" 2>/dev/null || true
    fi
    
    # Ansible configuration
    if [ -d "$PROJECT_ROOT/ansible" ]; then
        mkdir -p "$temp_dir/ansible"
        cp -r "$PROJECT_ROOT/ansible/inventory" "$temp_dir/ansible/" 2>/dev/null || true
        cp -r "$PROJECT_ROOT/ansible/playbooks" "$temp_dir/ansible/" 2>/dev/null || true
    fi
    
    # Database configuration
    if [ -f "$PROJECT_ROOT/config/databases.yml" ]; then
        mkdir -p "$temp_dir/config"
        cp "$PROJECT_ROOT/config/databases.yml" "$temp_dir/config/"
    fi
    
    # Docker configuration
    cp "$PROJECT_ROOT"/docker-compose*.yml "$temp_dir/" 2>/dev/null || true
    cp "$PROJECT_ROOT"/.env "$temp_dir/" 2>/dev/null || true
    
    # Create metadata file
    cat > "$temp_dir/metadata.json" <<EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "version": "1.0",
    "hostname": "$(hostname)",
    "user": "$(whoami)",
    "terraform_version": "$(terraform version -json 2>/dev/null | jq -r '.terraform_version' || echo 'unknown')",
    "ansible_version": "$(ansible --version | head -1 | awk '{print $2}' || echo 'unknown')"
}
EOF
    
    # Create tarball
    print_status "Creating backup archive..."
    tar -czf "$backup_file" -C "/tmp" "backup-${timestamp}"
    
    # Check backup size
    local backup_size=$(du -h "$backup_file" | cut -f1)
    print_success "Backup created: $backup_file (size: $backup_size)"
    
    # Verify backup
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        print_success "Backup verified successfully"
    else
        print_error "Backup verification failed"
        rm -f "$backup_file"
        return 1
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    # Upload to S3 if configured
    if [ -n "${BACKUP_S3_BUCKET:-}" ]; then
        print_status "Uploading backup to S3..."
        if aws s3 cp "$backup_file" "s3://${BACKUP_S3_BUCKET}/monitoring-backups/"; then
            print_success "Backup uploaded to S3"
        else
            print_warning "Failed to upload backup to S3"
        fi
    fi
}

# Restore from backup
restore_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi
    
    print_step "Restoring from backup: $(basename "$backup_file")"
    
    # Verify backup
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        print_error "Invalid backup file"
        return 1
    fi
    
    # Extract to temporary directory
    local temp_dir="/tmp/restore-$(date +%s)"
    mkdir -p "$temp_dir"
    
    print_status "Extracting backup..."
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Find backup directory
    local backup_dir=$(find "$temp_dir" -name "backup-*" -type d | head -1)
    if [ -z "$backup_dir" ]; then
        print_error "Invalid backup structure"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Show backup metadata
    if [ -f "$backup_dir/metadata.json" ]; then
        print_info "Backup metadata:"
        jq '.' "$backup_dir/metadata.json"
    fi
    
    # Confirm restore
    print_warning "This will overwrite existing configuration!"
    read -p "Continue with restore? (yes/no) " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Restore cancelled"
        rm -rf "$temp_dir"
        return 0
    fi
    
    # Restore files
    print_status "Restoring configuration files..."
    
    # Terraform
    if [ -d "$backup_dir/terraform" ]; then
        ensure_directory "$TERRAFORM_DIR"
        cp -r "$backup_dir/terraform"/* "$TERRAFORM_DIR/"
        print_check_success "Restored Terraform configuration"
    fi
    
    # Ansible
    if [ -d "$backup_dir/ansible" ]; then
        ensure_directory "$PROJECT_ROOT/ansible"
        cp -r "$backup_dir/ansible"/* "$PROJECT_ROOT/ansible/"
        print_check_success "Restored Ansible configuration"
    fi
    
    # Config
    if [ -d "$backup_dir/config" ]; then
        ensure_directory "$PROJECT_ROOT/config"
        cp -r "$backup_dir/config"/* "$PROJECT_ROOT/config/"
        print_check_success "Restored database configuration"
    fi
    
    # Docker files
    if ls "$backup_dir"/docker-compose*.yml >/dev/null 2>&1; then
        cp "$backup_dir"/docker-compose*.yml "$PROJECT_ROOT/"
        print_check_success "Restored Docker configuration"
    fi
    
    if [ -f "$backup_dir/.env" ]; then
        cp "$backup_dir/.env" "$PROJECT_ROOT/"
        print_check_success "Restored environment file"
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    print_success "Restore completed successfully"
    print_info "You may need to run 'terraform init' to reinitialize Terraform"
}

# Rotate old backups
rotate_backups() {
    print_step "Rotating old backups"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        print_info "No backup directory found"
        return 0
    fi
    
    # Find and remove old backups
    print_status "Removing backups older than $RETENTION_DAYS days..."
    local count=0
    while IFS= read -r backup_file; do
        if [ -f "$backup_file" ]; then
            print_check_success "Removed: $(basename "$backup_file")"
            rm -f "$backup_file"
            ((count++))
        fi
    done < <(find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f -mtime +$RETENTION_DAYS)
    
    if [ $count -eq 0 ]; then
        print_info "No old backups to remove"
    else
        print_success "Removed $count old backup(s)"
    fi
    
    # Rotate logs
    print_status "Rotating old log files..."
    count=0
    while IFS= read -r log_file; do
        if [ -f "$log_file" ]; then
            rm -f "$log_file"
            ((count++))
        fi
    done < <(find "$PROJECT_ROOT" -name "*.log" -type f -mtime +$LOG_RETENTION_DAYS)
    
    if [ $count -gt 0 ]; then
        print_success "Removed $count old log file(s)"
    fi
    
    # Clean up empty directories
    find "$BACKUP_DIR" -type d -empty -delete 2>/dev/null || true
}

# Show status
show_status() {
    print_step "System Status"
    
    # Terraform status
    print_status "Terraform Status:"
    if [ -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
        local resource_count=$(terraform -chdir="$TERRAFORM_DIR" state list 2>/dev/null | wc -l || echo "0")
        print_check_success "Terraform state exists ($resource_count resources)"
    else
        print_check_fail "No Terraform state found"
    fi
    
    # Docker status
    print_status "Docker Status:"
    local running_containers=$(docker-compose ps -q 2>/dev/null | wc -l || echo "0")
    if [ "$running_containers" -gt 0 ]; then
        print_check_success "$running_containers container(s) running"
        docker-compose ps 2>/dev/null || true
    else
        print_check_warning "No containers running"
    fi
    
    # Backup status
    print_status "Backup Status:"
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=$(find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f 2>/dev/null | wc -l)
        local latest_backup=$(find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        
        if [ -n "$latest_backup" ]; then
            local backup_age=$(( ($(date +%s) - $(stat -c %Y "$latest_backup" 2>/dev/null || stat -f %m "$latest_backup" 2>/dev/null)) / 86400 ))
            print_check_success "$backup_count backup(s) found"
            print_info "Latest backup: $(basename "$latest_backup") ($backup_age days old)"
        else
            print_check_warning "No backups found"
        fi
    else
        print_check_warning "Backup directory not found"
    fi
    
    # Disk usage
    print_status "Disk Usage:"
    local project_size=$(du -sh "$PROJECT_ROOT" 2>/dev/null | cut -f1)
    print_info "Project size: $project_size"
    
    if [ -d "$BACKUP_DIR" ]; then
        local backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "0")
        print_info "Backup size: $backup_size"
    fi
}

# Health check
health_check() {
    print_step "Health Check"
    
    local all_healthy=true
    
    # Check AWS connectivity
    print_status "AWS Connectivity:"
    if timeout 10 aws sts get-caller-identity >/dev/null 2>&1; then
        print_check_success "AWS API accessible"
    else
        print_check_fail "AWS API not accessible"
        all_healthy=false
    fi
    
    # Check Docker
    print_status "Docker Health:"
    if docker info >/dev/null 2>&1; then
        print_check_success "Docker daemon running"
    else
        print_check_fail "Docker daemon not running"
        all_healthy=false
    fi
    
    # Check services if running
    if docker-compose ps -q 2>/dev/null | grep -q .; then
        print_status "Service Health:"
        
        # Check each service
        for service in localstack mysql-test postgres-test newrelic-mock; do
            if docker-compose ps "$service" 2>/dev/null | grep -q "Up"; then
                print_check_success "$service is healthy"
            else
                print_check_fail "$service is not healthy"
                all_healthy=false
            fi
        done
    fi
    
    # Check disk space
    print_status "Disk Space:"
    local disk_usage=$(df -h "$PROJECT_ROOT" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -lt 80 ]; then
        print_check_success "Sufficient disk space (${disk_usage}% used)"
    elif [ "$disk_usage" -lt 90 ]; then
        print_check_warning "Low disk space (${disk_usage}% used)"
    else
        print_check_fail "Critical disk space (${disk_usage}% used)"
        all_healthy=false
    fi
    
    # Summary
    echo
    if [ "$all_healthy" = true ]; then
        print_success "All health checks passed"
        return 0
    else
        print_error "Some health checks failed"
        return 1
    fi
}

# Main execution
main() {
    local command="${1:-}"
    shift || true
    
    case "$command" in
        backup)
            create_backup "$@"
            ;;
        restore)
            local backup_file=""
            while [[ $# -gt 0 ]]; do
                case $1 in
                    -f|--file)
                        backup_file="$2"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done
            
            if [ -z "$backup_file" ]; then
                print_error "No backup file specified"
                echo "Usage: $(basename "$0") restore --file <backup-file>"
                exit 1
            fi
            
            restore_backup "$backup_file"
            ;;
        rotate)
            while [[ $# -gt 0 ]]; do
                case $1 in
                    -r|--retention)
                        RETENTION_DAYS="$2"
                        shift 2
                        ;;
                    -l|--log-retention)
                        LOG_RETENTION_DAYS="$2"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done
            rotate_backups
            ;;
        status)
            show_status
            ;;
        health-check)
            health_check
            ;;
        -h|--help|"")
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"