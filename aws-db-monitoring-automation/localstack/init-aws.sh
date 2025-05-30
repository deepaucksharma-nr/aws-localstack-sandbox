#!/bin/bash

echo "Initializing LocalStack AWS resources..."

# Create VPC
VPC_ID=$(awslocal ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
echo "Created VPC: $VPC_ID"

# Create subnet
SUBNET_ID=$(awslocal ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone us-east-1a \
    --query 'Subnet.SubnetId' \
    --output text)
echo "Created Subnet: $SUBNET_ID"

# Create Internet Gateway
IGW_ID=$(awslocal ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
awslocal ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
echo "Created and attached Internet Gateway: $IGW_ID"

# Create route table
ROUTE_TABLE_ID=$(awslocal ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
awslocal ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
awslocal ec2 associate-route-table --subnet-id $SUBNET_ID --route-table-id $ROUTE_TABLE_ID
echo "Created and configured Route Table: $ROUTE_TABLE_ID"

# Create SSH key pair
awslocal ec2 create-key-pair --key-name test-key --query 'KeyMaterial' --output text > /tmp/test-key.pem
chmod 600 /tmp/test-key.pem
echo "Created SSH key pair: test-key"

# Store IDs in SSM parameters for Terraform to use
awslocal ssm put-parameter --name "/test/vpc-id" --value "$VPC_ID" --type String
awslocal ssm put-parameter --name "/test/subnet-id" --value "$SUBNET_ID" --type String

echo "LocalStack initialization complete!"