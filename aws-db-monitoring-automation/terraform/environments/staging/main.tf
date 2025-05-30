# Staging Environment Configuration
# Uses RDS instances for databases

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
  
  backend "s3" {
    # Configure backend as needed
    # bucket = "your-terraform-state-bucket"
    # key    = "db-monitoring/staging/terraform.tfstate"
    # region = "us-east-1"
  }
}

# Provider configuration
provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "db-monitoring"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "newrelic_license_key" {
  description = "New Relic license key"
  type        = string
  sensitive   = true
}

# Local values
locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
    Monitor     = "newrelic"
  }
  
  azs = data.aws_availability_zones.available.names
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module (simplified for staging)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

# Public subnets for NAT gateways
resource "aws_subnet" "public" {
  count = 2
  
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-${local.azs[count.index]}"
    Type = "public"
  })
}

# Private subnets for RDS
resource "aws_subnet" "private" {
  count = 2
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.azs[count.index]
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-${local.azs[count.index]}"
    Type = "private"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

# Elastic IPs for NAT
resource "aws_eip" "nat" {
  count  = 1  # Single NAT for staging to save costs
  domain = "vpc"
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip-${count.index + 1}"
  })
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  count = 1  # Single NAT for staging
  
  subnet_id     = aws_subnet.public[0].id
  allocation_id = aws_eip.nat[0].id
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-${count.index + 1}"
  })
  
  depends_on = [aws_internet_gateway.main]
}

# Route tables
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

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-private-rt"
  })
}

# Route table associations
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security group for monitoring server
resource "aws_security_group" "monitoring" {
  name        = "${var.project_name}-${var.environment}-monitoring-sg"
  description = "Security group for New Relic monitoring server"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
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

# RDS MySQL Instance
module "mysql_rds" {
  source = "../../modules/rds-mysql"
  
  identifier = "${var.project_name}-${var.environment}-mysql"
  
  # Database configuration
  engine_version    = "8.0.35"
  instance_class    = "db.t3.small"
  allocated_storage = 50
  storage_type      = "gp3"
  
  # Network configuration
  vpc_id             = aws_vpc.main.id
  subnet_ids         = aws_subnet.private[*].id
  allowed_cidr_blocks = [var.vpc_cidr]
  
  # High availability (disabled for staging)
  multi_az = false
  
  # Backup
  backup_retention_period = 7
  
  # Monitoring
  monitoring_interval          = 60
  performance_insights_enabled = false  # Save costs in staging
  
  # New Relic
  create_newrelic_user = true
  
  tags = merge(local.common_tags, {
    Name     = "${var.project_name}-${var.environment}-mysql"
    Database = "mysql"
  })
}

# RDS PostgreSQL Instance
module "postgres_rds" {
  source = "../../modules/rds-postgresql"
  
  identifier = "${var.project_name}-${var.environment}-postgres"
  
  # Database configuration
  engine_version    = "15.4"
  instance_class    = "db.t3.small"
  allocated_storage = 50
  storage_type      = "gp3"
  database_name     = "staging"
  
  # Network configuration
  vpc_id             = aws_vpc.main.id
  subnet_ids         = aws_subnet.private[*].id
  allowed_cidr_blocks = [var.vpc_cidr]
  
  # High availability (disabled for staging)
  multi_az = false
  
  # Backup
  backup_retention_period = 7
  
  # Monitoring
  monitoring_interval          = 60
  performance_insights_enabled = false  # Save costs in staging
  enable_pg_stat_statements    = true
  
  # New Relic
  create_newrelic_user = true
  
  tags = merge(local.common_tags, {
    Name     = "${var.project_name}-${var.environment}-postgres"
    Database = "postgresql"
  })
}

# EC2 Instance for monitoring
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "monitoring" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.small"
  subnet_id     = aws_subnet.private[0].id
  
  vpc_security_group_ids = [
    aws_security_group.monitoring.id,
    module.mysql_rds.security_group_id,
    module.postgres_rds.security_group_id
  ]
  
  iam_instance_profile = aws_iam_instance_profile.monitoring.name
  
  user_data = templatefile("${path.module}/userdata.sh", {
    environment          = var.environment
    newrelic_license_key = var.newrelic_license_key
  })
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-monitoring"
    Role = "monitoring"
  })
}

# IAM role for monitoring instance
resource "aws_iam_role" "monitoring" {
  name = "${var.project_name}-${var.environment}-monitoring-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policy for accessing secrets
resource "aws_iam_role_policy" "monitoring_secrets" {
  name = "${var.project_name}-${var.environment}-monitoring-secrets"
  role = aws_iam_role.monitoring.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          module.mysql_rds.newrelic_password_secret_name != null ? "arn:aws:secretsmanager:${var.aws_region}:*:secret:${module.mysql_rds.newrelic_password_secret_name}*" : "",
          module.postgres_rds.newrelic_password_secret_name != null ? "arn:aws:secretsmanager:${var.aws_region}:*:secret:${module.postgres_rds.newrelic_password_secret_name}*" : ""
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.environment}/*"
      }
    ]
  })
}

# Attach CloudWatch policy
resource "aws_iam_role_policy_attachment" "monitoring_cloudwatch" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance profile
resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.project_name}-${var.environment}-monitoring-profile"
  role = aws_iam_role.monitoring.name
}

# Store configuration in SSM
resource "aws_ssm_parameter" "database_config" {
  name = "/${var.environment}/newrelic/database-config"
  type = "String"
  value = jsonencode({
    mysql_databases = [
      {
        name     = module.mysql_rds.instance_id
        type     = "mysql"
        provider = "rds"
        connection = {
          endpoint = module.mysql_rds.endpoint
          port     = module.mysql_rds.port
        }
        credentials = {
          username        = module.mysql_rds.newrelic_user
          password_source = "aws_secrets_manager"
          password_key    = module.mysql_rds.newrelic_password_secret_name
        }
        monitoring = {
          collect_inventory      = true
          extended_metrics       = true
          collect_rds_metrics    = true
          enable_query_monitoring = true
        }
        labels = {
          environment = var.environment
        }
      }
    ]
    postgresql_databases = [
      {
        name     = module.postgres_rds.instance_id
        type     = "postgresql"
        provider = "rds"
        connection = {
          endpoint = module.postgres_rds.endpoint
          port     = module.postgres_rds.port
          database = module.postgres_rds.database_name
        }
        credentials = {
          username        = module.postgres_rds.newrelic_user
          password_source = "aws_secrets_manager"
          password_key    = module.postgres_rds.newrelic_password_secret_name
        }
        monitoring = {
          collect_inventory       = true
          extended_metrics        = true
          collect_rds_metrics     = true
          enable_query_monitoring = true
          collect_bloat_metrics   = true
          collect_db_lock_metrics = true
        }
        labels = {
          environment = var.environment
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Outputs
output "monitoring_instance_id" {
  description = "ID of the monitoring EC2 instance"
  value       = aws_instance.monitoring.id
}

output "mysql_endpoint" {
  description = "MySQL RDS endpoint"
  value       = module.mysql_rds.endpoint
}

output "postgres_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = module.postgres_rds.endpoint
}

output "database_config_parameter" {
  description = "SSM parameter containing database configuration"
  value       = aws_ssm_parameter.database_config.name
}

output "environment_summary" {
  description = "Environment configuration summary"
  value = {
    environment = var.environment
    region      = var.aws_region
    vpc_id      = aws_vpc.main.id
    databases   = {
      mysql = {
        type     = "rds"
        endpoint = module.mysql_rds.endpoint
        instance = module.mysql_rds.instance_id
      }
      postgresql = {
        type     = "rds"
        endpoint = module.postgres_rds.endpoint
        instance = module.postgres_rds.instance_id
      }
    }
  }
}