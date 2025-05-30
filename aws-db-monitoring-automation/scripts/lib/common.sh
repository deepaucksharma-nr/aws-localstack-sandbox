#!/usr/bin/env bash

# Common functions and utilities for AWS DB monitoring scripts
# This library provides shared functionality across all scripts

# Color definitions
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Logging functions
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

# Alternative logging styles for specific contexts
print_test_status() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_test_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_test_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_check_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_check_fail() {
    echo -e "${RED}[✗]${NC} $1"
}

print_check_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Script directory resolution
get_script_dir() {
    echo "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
}

get_project_root() {
    local script_dir="${1:-$(get_script_dir)}"
    # Navigate up from lib directory to find project root
    echo "$(cd "$script_dir/../.." && pwd)"
}

# Utility functions
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        print_error "$cmd is not installed"
        return 1
    fi
    return 0
}

check_required_commands() {
    local commands=("$@")
    local missing=()
    
    for cmd in "${commands[@]}"; do
        if ! check_command "$cmd"; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required commands: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Service health check
wait_for_service() {
    local service="$1"
    local host="${2:-localhost}"
    local port="$3"
    local timeout="${4:-30}"
    local elapsed=0
    
    print_status "Waiting for $service on $host:$port..."
    
    while ! nc -z "$host" "$port" >/dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            print_error "$service failed to start within $timeout seconds"
            return 1
        fi
        sleep 1
        ((elapsed++))
    done
    
    print_success "$service is ready on $host:$port"
    return 0
}

# Process management
is_process_running() {
    local process_name="$1"
    pgrep -f "$process_name" > /dev/null 2>&1
}

kill_process_by_name() {
    local process_name="$1"
    if is_process_running "$process_name"; then
        pkill -f "$process_name"
        print_status "Stopped $process_name"
    fi
}

# File and directory utilities
ensure_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        print_status "Created directory: $dir"
    fi
}

# Timestamp utilities
get_timestamp() {
    date '+%Y%m%d_%H%M%S'
}

get_iso_timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# Error handling
handle_error() {
    local exit_code="$1"
    local error_message="${2:-Command failed}"
    
    if [ "$exit_code" -ne 0 ]; then
        print_error "$error_message (exit code: $exit_code)"
        exit "$exit_code"
    fi
}

# Cleanup handling
setup_cleanup() {
    local cleanup_function="$1"
    trap "$cleanup_function" EXIT INT TERM
}

# JSON utilities (requires jq)
validate_json() {
    local json_file="$1"
    if ! jq empty "$json_file" >/dev/null 2>&1; then
        print_error "Invalid JSON in file: $json_file"
        return 1
    fi
    return 0
}

# YAML utilities (requires yq)
validate_yaml() {
    local yaml_file="$1"
    if command -v yq &> /dev/null; then
        if ! yq eval '.' "$yaml_file" >/dev/null 2>&1; then
            print_error "Invalid YAML in file: $yaml_file"
            return 1
        fi
    else
        print_warning "yq not installed, skipping YAML validation"
    fi
    return 0
}

# Configuration file handling
load_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        print_error "Configuration file not found: $config_file"
        return 1
    fi
    
    case "$config_file" in
        *.json)
            validate_json "$config_file" || return 1
            ;;
        *.yml|*.yaml)
            validate_yaml "$config_file" || return 1
            ;;
    esac
    
    return 0
}

# AWS utilities
check_aws_credentials() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured or invalid"
        return 1
    fi
    return 0
}

get_aws_region() {
    echo "${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-1}}"
}

# Docker utilities
is_docker_running() {
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running"
        return 1
    fi
    return 0
}

# Terraform utilities
check_terraform_installed() {
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed"
        return 1
    fi
    return 0
}

# Progress indicators
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Note: Do not export SCRIPT_DIR or PROJECT_ROOT here to avoid conflicts
# Each script should define its own paths