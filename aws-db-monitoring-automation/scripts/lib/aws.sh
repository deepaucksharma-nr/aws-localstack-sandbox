#!/usr/bin/env bash

# AWS and LocalStack utilities for AWS DB monitoring scripts
# This library provides cloud infrastructure operations

# Source common functions
AWS_LIB_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${AWS_LIB_DIR}/common.sh"

# AWS Configuration
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_PAGER=""  # Disable AWS CLI pager

# LocalStack Configuration
export LOCALSTACK_ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
export LOCALSTACK_REGION="${LOCALSTACK_REGION:-us-east-1}"

# AWS CLI wrapper for LocalStack
awslocal() {
    aws --endpoint-url="$LOCALSTACK_ENDPOINT" "$@"
}

# Check if running against LocalStack
is_localstack() {
    [ -n "${AWS_ENDPOINT_URL:-}" ] || [ "${USE_LOCALSTACK:-false}" == "true" ]
}

# Get appropriate AWS command
get_aws_cmd() {
    if is_localstack; then
        echo "awslocal"
    else
        echo "aws"
    fi
}

# Wait for LocalStack to be ready
wait_for_localstack() {
    local timeout="${1:-60}"
    local elapsed=0
    
    print_status "Waiting for LocalStack to be ready..."
    
    while [ $elapsed -lt $timeout ]; do
        if curl -s "${LOCALSTACK_ENDPOINT}/_localstack/health" | grep -q '"services":'; then
            print_success "LocalStack is ready"
            return 0
        fi
        sleep 2
        ((elapsed+=2))
    done
    
    print_error "LocalStack failed to start within $timeout seconds"
    return 1
}

# Initialize LocalStack environment
init_localstack_env() {
    if is_localstack; then
        export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
        export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
        export AWS_ENDPOINT_URL="$LOCALSTACK_ENDPOINT"
        print_status "LocalStack environment initialized"
    fi
}

# VPC Management
create_vpc() {
    local cidr_block="${1:-10.0.0.0/16}"
    local name="${2:-monitoring-vpc}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Creating VPC with CIDR: $cidr_block"
    
    local vpc_id=$($aws_cmd ec2 create-vpc \
        --cidr-block "$cidr_block" \
        --query 'Vpc.VpcId' \
        --output text)
    
    if [ -n "$vpc_id" ]; then
        # Enable DNS hostnames and support
        $aws_cmd ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-hostnames
        $aws_cmd ec2 modify-vpc-attribute --vpc-id "$vpc_id" --enable-dns-support
        
        # Tag the VPC
        $aws_cmd ec2 create-tags --resources "$vpc_id" --tags "Key=Name,Value=$name"
        
        print_success "Created VPC: $vpc_id"
        echo "$vpc_id"
    else
        print_error "Failed to create VPC"
        return 1
    fi
}

# Subnet Management
create_subnet() {
    local vpc_id="$1"
    local cidr_block="${2:-10.0.1.0/24}"
    local name="${3:-monitoring-subnet}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Creating subnet in VPC $vpc_id with CIDR: $cidr_block"
    
    local subnet_id=$($aws_cmd ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "$cidr_block" \
        --query 'Subnet.SubnetId' \
        --output text)
    
    if [ -n "$subnet_id" ]; then
        # Tag the subnet
        $aws_cmd ec2 create-tags --resources "$subnet_id" --tags "Key=Name,Value=$name"
        
        print_success "Created subnet: $subnet_id"
        echo "$subnet_id"
    else
        print_error "Failed to create subnet"
        return 1
    fi
}

# Internet Gateway Management
create_internet_gateway() {
    local vpc_id="$1"
    local name="${2:-monitoring-igw}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Creating Internet Gateway for VPC: $vpc_id"
    
    # Create IGW
    local igw_id=$($aws_cmd ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' \
        --output text)
    
    if [ -n "$igw_id" ]; then
        # Attach to VPC
        $aws_cmd ec2 attach-internet-gateway \
            --vpc-id "$vpc_id" \
            --internet-gateway-id "$igw_id"
        
        # Tag the IGW
        $aws_cmd ec2 create-tags --resources "$igw_id" --tags "Key=Name,Value=$name"
        
        print_success "Created and attached Internet Gateway: $igw_id"
        echo "$igw_id"
    else
        print_error "Failed to create Internet Gateway"
        return 1
    fi
}

# Security Group Management
create_security_group() {
    local vpc_id="$1"
    local name="${2:-monitoring-sg}"
    local description="${3:-Security group for monitoring infrastructure}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Creating security group: $name"
    
    local sg_id=$($aws_cmd ec2 create-security-group \
        --group-name "$name" \
        --description "$description" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' \
        --output text)
    
    if [ -n "$sg_id" ]; then
        # Tag the security group
        $aws_cmd ec2 create-tags --resources "$sg_id" --tags "Key=Name,Value=$name"
        
        print_success "Created security group: $sg_id"
        echo "$sg_id"
    else
        print_error "Failed to create security group"
        return 1
    fi
}

# Add security group rule
add_security_group_rule() {
    local sg_id="$1"
    local protocol="$2"
    local port="$3"
    local source="${4:-0.0.0.0/0}"
    local description="${5:-}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Adding rule to security group $sg_id: $protocol/$port from $source"
    
    local cmd="$aws_cmd ec2 authorize-security-group-ingress --group-id $sg_id --protocol $protocol"
    
    if [ "$port" == "-1" ]; then
        cmd="$cmd --port -1"
    else
        cmd="$cmd --port $port"
    fi
    
    if [ -n "$description" ]; then
        cmd="$cmd --ip-permissions IpProtocol=$protocol,FromPort=$port,ToPort=$port,IpRanges=[{CidrIp=$source,Description=\"$description\"}]"
    else
        cmd="$cmd --cidr $source"
    fi
    
    if $cmd 2>/dev/null; then
        print_success "Added security group rule"
    else
        print_warning "Rule may already exist or failed to add"
    fi
}

# IAM Role Management
create_iam_role() {
    local role_name="$1"
    local policy_document="${2:-}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Creating IAM role: $role_name"
    
    # Default trust policy if not provided
    if [ -z "$policy_document" ]; then
        policy_document='{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "ec2.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }'
    fi
    
    if $aws_cmd iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$policy_document" >/dev/null 2>&1; then
        print_success "Created IAM role: $role_name"
        return 0
    else
        print_warning "IAM role may already exist: $role_name"
        return 1
    fi
}

# Create instance profile
create_instance_profile() {
    local profile_name="$1"
    local role_name="${2:-$profile_name}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Creating instance profile: $profile_name"
    
    # Create instance profile
    if $aws_cmd iam create-instance-profile \
        --instance-profile-name "$profile_name" >/dev/null 2>&1; then
        
        # Add role to instance profile
        $aws_cmd iam add-role-to-instance-profile \
            --instance-profile-name "$profile_name" \
            --role-name "$role_name" >/dev/null 2>&1
        
        print_success "Created instance profile: $profile_name"
        return 0
    else
        print_warning "Instance profile may already exist: $profile_name"
        return 1
    fi
}

# Secrets Manager
create_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local description="${3:-}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Creating secret: $secret_name"
    
    local cmd="$aws_cmd secretsmanager create-secret --name \"$secret_name\" --secret-string \"$secret_value\""
    
    if [ -n "$description" ]; then
        cmd="$cmd --description \"$description\""
    fi
    
    if eval "$cmd" >/dev/null 2>&1; then
        print_success "Created secret: $secret_name"
        return 0
    else
        print_warning "Secret may already exist: $secret_name"
        return 1
    fi
}

# Get secret value
get_secret() {
    local secret_name="$1"
    local aws_cmd=$(get_aws_cmd)
    
    $aws_cmd secretsmanager get-secret-value \
        --secret-id "$secret_name" \
        --query 'SecretString' \
        --output text 2>/dev/null
}

# SSM Parameter Store
put_parameter() {
    local name="$1"
    local value="$2"
    local type="${3:-String}"
    local description="${4:-}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Storing parameter: $name"
    
    local cmd="$aws_cmd ssm put-parameter --name \"$name\" --value \"$value\" --type \"$type\" --overwrite"
    
    if [ -n "$description" ]; then
        cmd="$cmd --description \"$description\""
    fi
    
    if eval "$cmd" >/dev/null 2>&1; then
        print_success "Stored parameter: $name"
        return 0
    else
        print_error "Failed to store parameter: $name"
        return 1
    fi
}

# Get parameter value
get_parameter() {
    local name="$1"
    local aws_cmd=$(get_aws_cmd)
    
    $aws_cmd ssm get-parameter \
        --name "$name" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text 2>/dev/null
}

# KMS Key Management
create_kms_key() {
    local description="${1:-Monitoring encryption key}"
    local alias="${2:-}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Creating KMS key"
    
    local key_id=$($aws_cmd kms create-key \
        --description "$description" \
        --query 'KeyMetadata.KeyId' \
        --output text)
    
    if [ -n "$key_id" ]; then
        print_success "Created KMS key: $key_id"
        
        # Create alias if provided
        if [ -n "$alias" ]; then
            $aws_cmd kms create-alias \
                --alias-name "alias/$alias" \
                --target-key-id "$key_id" >/dev/null 2>&1
            print_success "Created alias: alias/$alias"
        fi
        
        echo "$key_id"
        return 0
    else
        print_error "Failed to create KMS key"
        return 1
    fi
}

# EC2 Key Pair Management
create_key_pair() {
    local key_name="$1"
    local save_path="${2:-}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Creating key pair: $key_name"
    
    local key_material=$($aws_cmd ec2 create-key-pair \
        --key-name "$key_name" \
        --query 'KeyMaterial' \
        --output text 2>/dev/null)
    
    if [ -n "$key_material" ]; then
        if [ -n "$save_path" ]; then
            echo "$key_material" > "$save_path"
            chmod 600 "$save_path"
            print_success "Created key pair and saved to: $save_path"
        else
            print_success "Created key pair: $key_name"
        fi
        return 0
    else
        print_warning "Key pair may already exist: $key_name"
        return 1
    fi
}

# Check resource existence
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    local aws_cmd=$(get_aws_cmd)
    
    case "$resource_type" in
        vpc)
            $aws_cmd ec2 describe-vpcs --vpc-ids "$resource_id" >/dev/null 2>&1
            ;;
        subnet)
            $aws_cmd ec2 describe-subnets --subnet-ids "$resource_id" >/dev/null 2>&1
            ;;
        security-group)
            $aws_cmd ec2 describe-security-groups --group-ids "$resource_id" >/dev/null 2>&1
            ;;
        instance)
            $aws_cmd ec2 describe-instances --instance-ids "$resource_id" >/dev/null 2>&1
            ;;
        role)
            $aws_cmd iam get-role --role-name "$resource_id" >/dev/null 2>&1
            ;;
        secret)
            $aws_cmd secretsmanager describe-secret --secret-id "$resource_id" >/dev/null 2>&1
            ;;
        parameter)
            $aws_cmd ssm get-parameter --name "$resource_id" >/dev/null 2>&1
            ;;
        *)
            print_error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# Get instance IP
get_instance_ip() {
    local instance_id="$1"
    local ip_type="${2:-public}"
    local aws_cmd=$(get_aws_cmd)
    
    local query
    if [ "$ip_type" == "public" ]; then
        query='Reservations[0].Instances[0].PublicIpAddress'
    else
        query='Reservations[0].Instances[0].PrivateIpAddress'
    fi
    
    $aws_cmd ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query "$query" \
        --output text 2>/dev/null
}

# Wait for instance to be running
wait_for_instance_running() {
    local instance_id="$1"
    local timeout="${2:-300}"
    local aws_cmd=$(get_aws_cmd)
    
    print_status "Waiting for instance $instance_id to be running..."
    
    if $aws_cmd ec2 wait instance-running \
        --instance-ids "$instance_id" \
        --cli-read-timeout "$timeout" 2>/dev/null; then
        print_success "Instance is running: $instance_id"
        return 0
    else
        print_error "Instance failed to reach running state: $instance_id"
        return 1
    fi
}

# Tag resource
tag_resource() {
    local resource_id="$1"
    local key="$2"
    local value="$3"
    local aws_cmd=$(get_aws_cmd)
    
    $aws_cmd ec2 create-tags \
        --resources "$resource_id" \
        --tags "Key=$key,Value=$value" >/dev/null 2>&1
}