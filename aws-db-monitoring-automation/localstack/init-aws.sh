#!/usr/bin/env bash

# LocalStack initialization script
# Consolidated script for initializing AWS resources in LocalStack

set -euo pipefail

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$(dirname "$SCRIPT_DIR")/scripts/lib"

# Source libraries
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/aws.sh"

# Default values
MODE="basic"
REGION="us-east-1"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"

# Usage information
usage() {
    cat << EOF
LocalStack Initialization Script
Part of AWS DB Monitoring Automation

Usage: $(basename "$0") [options]

Options:
    --mode MODE         Initialization mode (basic, enhanced, full) [default: basic]
    --region REGION     AWS region [default: us-east-1]
    --vpc-cidr CIDR     VPC CIDR block [default: 10.0.0.0/16]
    --subnet-cidr CIDR  Subnet CIDR block [default: 10.0.1.0/24]
    -h, --help          Show this help message

Modes:
    basic       Create basic networking resources (VPC, subnet, IGW)
    enhanced    Basic + security groups, IAM roles, KMS keys
    full        Enhanced + RDS simulation, complete monitoring setup

Examples:
    # Basic initialization
    $(basename "$0")
    
    # Enhanced initialization with custom VPC
    $(basename "$0") --mode enhanced --vpc-cidr 172.16.0.0/16
    
    # Full initialization for complete testing
    $(basename "$0") --mode full

EOF
}

# Initialize basic resources
init_basic_resources() {
    print_status "Initializing basic LocalStack resources..."
    
    # Create VPC
    local vpc_id=$(create_vpc "$VPC_CIDR" "localstack-vpc")
    if [ -z "$vpc_id" ]; then
        print_error "Failed to create VPC"
        return 1
    fi
    
    # Create subnet
    local subnet_id=$(create_subnet "$vpc_id" "$SUBNET_CIDR" "localstack-subnet")
    if [ -z "$subnet_id" ]; then
        print_error "Failed to create subnet"
        return 1
    fi
    
    # Create Internet Gateway
    local igw_id=$(create_internet_gateway "$vpc_id" "localstack-igw")
    if [ -z "$igw_id" ]; then
        print_error "Failed to create Internet Gateway"
        return 1
    fi
    
    # Create and configure route table
    print_status "Configuring route table..."
    local route_table_id=$(awslocal ec2 create-route-table \
        --vpc-id "$vpc_id" \
        --query 'RouteTable.RouteTableId' \
        --output text)
    
    awslocal ec2 create-route \
        --route-table-id "$route_table_id" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "$igw_id" >/dev/null
    
    awslocal ec2 associate-route-table \
        --subnet-id "$subnet_id" \
        --route-table-id "$route_table_id" >/dev/null
    
    # Create key pair
    create_key_pair "test-key"
    
    # Create basic AMI
    print_status "Creating test AMI..."
    local ami_id=$(awslocal ec2 register-image \
        --name "localstack-ami-test" \
        --description "Test AMI for LocalStack" \
        --architecture x86_64 \
        --root-device-name /dev/sda1 \
        --virtualization-type hvm \
        --query 'ImageId' \
        --output text)
    
    # Store resource IDs in SSM Parameter Store
    print_status "Storing resource IDs in Parameter Store..."
    put_parameter "/test/vpc-id" "$vpc_id" "String" "LocalStack VPC ID"
    put_parameter "/test/subnet-id" "$subnet_id" "String" "LocalStack Subnet ID"
    put_parameter "/test/ami-id" "$ami_id" "String" "LocalStack AMI ID"
    
    # Create basic secrets
    print_status "Creating basic secrets..."
    create_secret "test/db/mysql/password" "testpass123" "MySQL test password"
    create_secret "test/db/postgresql/password" "testpass123" "PostgreSQL test password"
    
    print_success "Basic resources initialized successfully"
    
    # Display summary
    echo
    echo "=== Basic Resources Created ==="
    echo "VPC ID: $vpc_id"
    echo "Subnet ID: $subnet_id"
    echo "Internet Gateway ID: $igw_id"
    echo "Route Table ID: $route_table_id"
    echo "AMI ID: $ami_id"
    echo "============================="
    
    return 0
}

# Initialize enhanced resources
init_enhanced_resources() {
    print_status "Initializing enhanced LocalStack resources..."
    
    # First create basic resources
    init_basic_resources || return 1
    
    # Get VPC ID from parameter store
    local vpc_id=$(get_parameter "/test/vpc-id")
    
    # Create security groups
    print_status "Creating security groups..."
    local monitoring_sg=$(create_security_group "$vpc_id" "localstack-monitoring-sg" "Security group for monitoring infrastructure")
    local db_sg=$(create_security_group "$vpc_id" "localstack-database-sg" "Security group for databases")
    
    # Add security group rules
    print_status "Configuring security group rules..."
    # Monitoring SG - Allow SSH and HTTPS
    add_security_group_rule "$monitoring_sg" "tcp" "22" "0.0.0.0/0" "SSH access"
    add_security_group_rule "$monitoring_sg" "tcp" "443" "0.0.0.0/0" "HTTPS access"
    
    # Database SG - Allow MySQL and PostgreSQL
    add_security_group_rule "$db_sg" "tcp" "3306" "0.0.0.0/0" "MySQL access"
    add_security_group_rule "$db_sg" "tcp" "5432" "0.0.0.0/0" "PostgreSQL access"
    
    # Create KMS key
    print_status "Creating KMS key..."
    local kms_key_id=$(create_kms_key "LocalStack test encryption key" "localstack-test")
    
    # Create IAM roles and policies
    print_status "Creating IAM roles and policies..."
    
    # Create monitoring role
    create_iam_role "localstack-monitoring-role"
    
    # Create monitoring policies
    local policy_doc='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "cloudwatch:PutMetricData",
                    "ec2:DescribeVolumes",
                    "ec2:DescribeTags",
                    "logs:PutLogEvents",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    awslocal iam put-role-policy \
        --role-name "localstack-monitoring-role" \
        --policy-name "MonitoringPolicy" \
        --policy-document "$policy_doc" >/dev/null
    
    # Create instance profile
    create_instance_profile "localstack-monitoring-profile" "localstack-monitoring-role"
    
    # Create CloudWatch Agent policy
    awslocal iam create-policy \
        --policy-name "CloudWatchAgentServerPolicy" \
        --policy-document "$policy_doc" >/dev/null 2>&1 || true
    
    # Create SSM policy
    awslocal iam create-policy \
        --policy-name "AmazonSSMManagedInstanceCore" \
        --policy-document "$policy_doc" >/dev/null 2>&1 || true
    
    # Store enhanced configuration in SSM
    print_status "Storing enhanced configuration..."
    put_parameter "/test/security-group/monitoring" "$monitoring_sg" "String" "Monitoring security group ID"
    put_parameter "/test/security-group/database" "$db_sg" "String" "Database security group ID"
    put_parameter "/test/kms-key-id" "$kms_key_id" "String" "KMS key ID"
    put_parameter "/test/iam-role" "localstack-monitoring-role" "String" "IAM role name"
    
    # Create database configuration
    local db_config='{
        "mysql": {
            "host": "mysql-test",
            "port": 3306,
            "database": "monitoring",
            "username": "newrelic"
        },
        "postgresql": {
            "host": "postgres-test",
            "port": 5432,
            "database": "monitoring",
            "username": "newrelic"
        }
    }'
    
    put_parameter "/localstack/newrelic/database-config" "$db_config" "SecureString" "Database configuration"
    
    print_success "Enhanced resources initialized successfully"
    
    # Display summary
    echo
    echo "=== Enhanced Resources Created ==="
    echo "Security Groups:"
    echo "  Monitoring: $monitoring_sg"
    echo "  Database: $db_sg"
    echo "KMS Key: $kms_key_id"
    echo "IAM Role: localstack-monitoring-role"
    echo "================================"
    
    return 0
}

# Initialize full resources (including RDS simulation)
init_full_resources() {
    print_status "Initializing full LocalStack resources..."
    
    # First create enhanced resources
    init_enhanced_resources || return 1
    
    # Get resource IDs
    local vpc_id=$(get_parameter "/test/vpc-id")
    local subnet_id=$(get_parameter "/test/subnet-id")
    local db_sg=$(get_parameter "/test/security-group/database")
    
    # Simulate RDS instances
    print_status "Creating simulated RDS instances..."
    
    # Create RDS subnet group
    awslocal rds create-db-subnet-group \
        --db-subnet-group-name "localstack-db-subnet-group" \
        --db-subnet-group-description "Subnet group for LocalStack testing" \
        --subnet-ids "$subnet_id" >/dev/null 2>&1 || true
    
    # Create parameter groups
    awslocal rds create-db-parameter-group \
        --db-parameter-group-name "localstack-mysql-params" \
        --db-parameter-group-family "mysql8.0" \
        --description "MySQL parameters for testing" >/dev/null 2>&1 || true
    
    awslocal rds create-db-parameter-group \
        --db-parameter-group-name "localstack-postgres-params" \
        --db-parameter-group-family "postgres13" \
        --description "PostgreSQL parameters for testing" >/dev/null 2>&1 || true
    
    # Store RDS endpoints
    put_parameter "/test/rds/mysql/endpoint" "mysql-test.localstack.localhost:3306" "String" "MySQL RDS endpoint"
    put_parameter "/test/rds/postgresql/endpoint" "postgres-test.localstack.localhost:5432" "String" "PostgreSQL RDS endpoint"
    
    # Create CloudWatch log groups
    print_status "Creating CloudWatch log groups..."
    awslocal logs create-log-group --log-group-name "/aws/rds/mysql/error" >/dev/null 2>&1 || true
    awslocal logs create-log-group --log-group-name "/aws/rds/mysql/general" >/dev/null 2>&1 || true
    awslocal logs create-log-group --log-group-name "/aws/rds/postgresql" >/dev/null 2>&1 || true
    
    # Create SNS topics for alerts
    print_status "Creating SNS topics..."
    local sns_topic=$(awslocal sns create-topic \
        --name "localstack-db-alerts" \
        --query 'TopicArn' \
        --output text)
    
    put_parameter "/test/sns/alerts-topic" "$sns_topic" "String" "SNS alerts topic ARN"
    
    # Create sample EC2 instance
    print_status "Creating monitoring instance..."
    local ami_id=$(get_parameter "/test/ami-id")
    local monitoring_sg=$(get_parameter "/test/security-group/monitoring")
    
    local instance_id=$(awslocal ec2 run-instances \
        --image-id "$ami_id" \
        --instance-type "t2.micro" \
        --key-name "test-key" \
        --security-group-ids "$monitoring_sg" \
        --subnet-id "$subnet_id" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=localstack-monitoring}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    put_parameter "/test/instance-id" "$instance_id" "String" "Monitoring instance ID"
    
    print_success "Full resources initialized successfully"
    
    # Display complete summary
    echo
    echo "=== Full LocalStack Environment ==="
    echo "VPC ID: $vpc_id"
    echo "Monitoring Instance: $instance_id"
    echo "MySQL Endpoint: mysql-test.localstack.localhost:3306"
    echo "PostgreSQL Endpoint: postgres-test.localstack.localhost:5432"
    echo "SNS Topic: $sns_topic"
    echo "=================================="
    echo
    echo "LocalStack is ready for testing!"
    echo "Use 'docker-compose ps' to verify services"
    
    return 0
}

# Cleanup resources
cleanup_resources() {
    print_status "Cleaning up LocalStack resources..."
    
    # This is a placeholder - LocalStack resources are ephemeral
    # and will be cleaned up when the container stops
    
    print_success "Cleanup complete"
    return 0
}

# Main function
main() {
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                MODE="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                export AWS_DEFAULT_REGION="$REGION"
                export LOCALSTACK_REGION="$REGION"
                shift 2
                ;;
            --vpc-cidr)
                VPC_CIDR="$2"
                shift 2
                ;;
            --subnet-cidr)
                SUBNET_CIDR="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            cleanup)
                cleanup_resources
                exit $?
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Ensure LocalStack is running
    if ! wait_for_localstack; then
        print_error "LocalStack is not running"
        print_status "Start LocalStack with: docker-compose up -d localstack"
        exit 1
    fi
    
    # Initialize LocalStack environment
    init_localstack_env
    
    # Execute based on mode
    case "$MODE" in
        basic)
            init_basic_resources
            ;;
        enhanced)
            init_enhanced_resources
            ;;
        full)
            init_full_resources
            ;;
        *)
            print_error "Unknown mode: $MODE"
            usage
            exit 1
            ;;
    esac
    
    exit $?
}

# Run main function
main "$@"