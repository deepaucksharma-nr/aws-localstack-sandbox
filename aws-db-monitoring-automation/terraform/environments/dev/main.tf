# Development Environment Configuration
# Uses local containers for databases (no RDS/Aurora)

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider configuration
provider "aws" {
  region = var.aws_region
  
  # For local development with LocalStack
  endpoints {
    ec2            = var.use_localstack ? "http://localhost:4566" : null
    iam            = var.use_localstack ? "http://localhost:4566" : null
    s3             = var.use_localstack ? "http://localhost:4566" : null
    ssm            = var.use_localstack ? "http://localhost:4566" : null
    secretsmanager = var.use_localstack ? "http://localhost:4566" : null
  }
  
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "use_localstack" {
  description = "Whether to use LocalStack for local development"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "db-monitoring"
}

# Local values
locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# VPC Configuration (minimal for dev)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-subnet"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Data source for AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Security group for monitoring server
resource "aws_security_group" "monitoring" {
  name        = "${var.project_name}-${var.environment}-monitoring-sg"
  description = "Security group for New Relic monitoring server"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    description = "SSH from anywhere (dev only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-monitoring-sg"
  })
}

# EC2 Instance for monitoring
resource "aws_instance" "monitoring" {
  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public.id
  
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  
  user_data = <<-EOF
    #!/bin/bash
    # Install Docker for container connectivity testing
    yum update -y
    amazon-linux-extras install docker -y
    service docker start
    usermod -a -G docker ec2-user
  EOF
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-monitoring"
    Role = "monitoring"
  })
}

# Store database endpoints for local containers
resource "aws_ssm_parameter" "mysql_endpoint" {
  name  = "/${var.environment}/database/mysql/endpoint"
  type  = "String"
  value = "mysql"  # Docker container name
  
  tags = local.common_tags
}

resource "aws_ssm_parameter" "postgres_endpoint" {
  name  = "/${var.environment}/database/postgres/endpoint"
  type  = "String"
  value = "postgres"  # Docker container name
  
  tags = local.common_tags
}

# Outputs
output "monitoring_instance_id" {
  description = "ID of the monitoring EC2 instance"
  value       = aws_instance.monitoring.id
}

output "monitoring_public_ip" {
  description = "Public IP of the monitoring instance"
  value       = aws_instance.monitoring.public_ip
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "environment_config" {
  description = "Environment configuration summary"
  value = {
    environment = var.environment
    region      = var.aws_region
    vpc_id      = aws_vpc.main.id
    databases   = {
      mysql = {
        type     = "container"
        endpoint = "mysql:3306"
      }
      postgresql = {
        type     = "container"
        endpoint = "postgres:5432"
      }
    }
  }
}