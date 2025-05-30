# Production Environment Configuration
# Uses Aurora clusters for high availability

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
    # key    = "db-monitoring/production/terraform.tfstate"
    # region = "us-east-1"
    # encrypt = true
    # dynamodb_table = "terraform-state-lock"
  }
}

# Provider configuration
provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "replica"
  region = var.replica_region
}

# Variables
variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "replica_region" {
  description = "Replica AWS region for Aurora Global Database"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "db-monitoring"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
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

# VPC Module
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr
  
  azs              = slice(local.azs, 0, 3)  # Use 3 AZs for production
  private_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i)]
  public_subnets   = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  database_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 20)]
  
  enable_nat_gateway     = true
  single_nat_gateway     = false  # High availability
  enable_dns_hostnames   = true
  enable_dns_support     = true
  
  # VPC endpoints for AWS services
  enable_s3_endpoint          = true
  enable_secretsmanager_endpoint = true
  enable_ssm_endpoint         = true
  
  create_database_subnet_group = true
  
  tags = local.common_tags
}

# KMS key for encryption
resource "aws_kms_key" "database" {
  description             = "KMS key for database encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-database-key"
  })
}

resource "aws_kms_alias" "database" {
  name          = "alias/${var.project_name}-${var.environment}-database"
  target_key_id = aws_kms_key.database.key_id
}

# Security group for monitoring servers
resource "aws_security_group" "monitoring" {
  name        = "${var.project_name}-${var.environment}-monitoring-sg"
  description = "Security group for New Relic monitoring servers"
  vpc_id      = module.vpc.vpc_id
  
  ingress {
    description = "SSH from bastion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
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

# Aurora MySQL Cluster
module "aurora_mysql" {
  source = "../../modules/aurora-mysql"
  
  cluster_identifier = "${var.project_name}-${var.environment}-mysql"
  
  # Engine configuration
  engine_version = "8.0.mysql_aurora.3.04.0"
  instance_class = "db.r6g.xlarge"
  instances      = 3  # Writer + 2 readers
  
  # Network configuration
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.database_subnets
  allowed_cidr_blocks = concat(
    module.vpc.private_subnets_cidr_blocks,
    module.vpc.database_subnets_cidr_blocks
  )
  
  # Storage encryption
  storage_encrypted = true
  kms_key_id        = aws_kms_key.database.arn
  
  # Backup configuration
  backup_retention_period = 30
  backtrack_window        = 72  # 72 hours of backtrack
  
  # High availability
  deletion_protection = true
  skip_final_snapshot = false
  
  # Monitoring
  performance_insights_enabled          = true
  performance_insights_retention_period = 731  # 2 years
  enabled_cloudwatch_logs_exports       = ["audit", "error", "general", "slowquery"]
  
  # New Relic
  create_newrelic_user = true
  
  # Global database (optional)
  # enable_global_cluster = true
  # global_cluster_identifier = "${var.project_name}-${var.environment}-mysql-global"
  
  tags = merge(local.common_tags, {
    Name     = "${var.project_name}-${var.environment}-mysql"
    Database = "mysql"
    Tier     = "production"
  })
}

# Aurora PostgreSQL Cluster
module "aurora_postgresql" {
  source = "../../modules/aurora-postgresql"
  
  cluster_identifier = "${var.project_name}-${var.environment}-postgres"
  
  # Engine configuration
  engine_version = "15.4"
  instance_class = "db.r6g.xlarge"
  instances      = 3  # Writer + 2 readers
  
  # Network configuration
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.database_subnets
  allowed_cidr_blocks = concat(
    module.vpc.private_subnets_cidr_blocks,
    module.vpc.database_subnets_cidr_blocks
  )
  
  # Storage encryption
  storage_encrypted = true
  kms_key_id        = aws_kms_key.database.arn
  
  # Backup configuration
  backup_retention_period = 30
  
  # High availability
  deletion_protection = true
  skip_final_snapshot = false
  
  # Monitoring
  performance_insights_enabled          = true
  performance_insights_retention_period = 731  # 2 years
  enabled_cloudwatch_logs_exports       = ["postgresql"]
  enable_pg_stat_statements             = true
  
  # New Relic
  create_newrelic_user = true
  
  tags = merge(local.common_tags, {
    Name     = "${var.project_name}-${var.environment}-postgres"
    Database = "postgresql"
    Tier     = "production"
  })
}

# Auto Scaling Group for monitoring instances
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

# Launch template for monitoring instances
resource "aws_launch_template" "monitoring" {
  name_prefix = "${var.project_name}-${var.environment}-monitoring-"
  
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.large"
  
  vpc_security_group_ids = [
    aws_security_group.monitoring.id,
    module.aurora_mysql.security_group_id,
    module.aurora_postgresql.security_group_id
  ]
  
  iam_instance_profile {
    name = aws_iam_instance_profile.monitoring.name
  }
  
  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    environment          = var.environment
    newrelic_license_key = var.newrelic_license_key
    mysql_cluster        = module.aurora_mysql.cluster_id
    postgres_cluster     = module.aurora_postgresql.cluster_id
  }))
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-${var.environment}-monitoring"
      Role = "monitoring"
    })
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "monitoring" {
  name               = "${var.project_name}-${var.environment}-monitoring-asg"
  vpc_zone_identifier = module.vpc.private_subnets
  
  min_size         = 2
  max_size         = 4
  desired_capacity = 3
  
  health_check_type         = "EC2"
  health_check_grace_period = 300
  
  launch_template {
    id      = aws_launch_template.monitoring.id
    version = "$Latest"
  }
  
  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-monitoring"
    propagate_at_launch = true
  }
  
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

# IAM role for monitoring instances
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

# IAM policies
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
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.project_name}-${var.environment}-*"
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
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.database.arn
      }
    ]
  })
}

# Attach managed policies
resource "aws_iam_role_policy_attachment" "monitoring_cloudwatch" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "monitoring_ssm" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile
resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.project_name}-${var.environment}-monitoring-profile"
  role = aws_iam_role.monitoring.name
}

# Store configuration in SSM Parameter Store
resource "aws_ssm_parameter" "database_config" {
  name  = "/${var.environment}/newrelic/database-config"
  type  = "SecureString"
  key_id = aws_kms_key.database.id
  value = jsonencode({
    mysql_databases = [
      {
        name     = module.aurora_mysql.cluster_id
        type     = "mysql"
        provider = "aurora"
        enabled  = true
        connection = {
          cluster_endpoint = module.aurora_mysql.cluster_endpoint
          reader_endpoint  = module.aurora_mysql.cluster_reader_endpoint
          port             = module.aurora_mysql.cluster_port
        }
        credentials = {
          username        = module.aurora_mysql.newrelic_user
          password_source = "aws_secrets_manager"
          password_key    = module.aurora_mysql.newrelic_password_secret_name
        }
        monitoring = {
          collect_inventory       = true
          extended_metrics        = true
          collect_aurora_metrics  = true
          monitor_readers         = true
          enable_query_monitoring = true
          query_metrics_interval  = "30s"
        }
        labels = {
          environment = var.environment
          region      = var.aws_region
          ha_enabled  = "true"
        }
      }
    ]
    postgresql_databases = [
      {
        name     = module.aurora_postgresql.cluster_id
        type     = "postgresql"
        provider = "aurora"
        enabled  = true
        connection = {
          cluster_endpoint = module.aurora_postgresql.cluster_endpoint
          reader_endpoint  = module.aurora_postgresql.cluster_reader_endpoint
          port             = module.aurora_postgresql.cluster_port
          database         = module.aurora_postgresql.database_name
          ssl_mode         = "require"
        }
        credentials = {
          username        = module.aurora_postgresql.newrelic_user
          password_source = "aws_secrets_manager"
          password_key    = module.aurora_postgresql.newrelic_password_secret_name
        }
        monitoring = {
          collect_inventory       = true
          extended_metrics        = true
          collect_aurora_metrics  = true
          monitor_readers         = true
          enable_query_monitoring = true
          collect_bloat_metrics   = true
          collect_db_lock_metrics = true
          pgbouncer_metrics       = false
        }
        labels = {
          environment = var.environment
          region      = var.aws_region
          ha_enabled  = "true"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "monitoring" {
  dashboard_name = "${var.project_name}-${var.environment}-database-monitoring"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", module.aurora_mysql.cluster_id],
            [".", ".", ".", module.aurora_postgresql.cluster_id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Database Connections"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", module.aurora_mysql.cluster_id],
            [".", ".", ".", module.aurora_postgresql.cluster_id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "CPU Utilization"
        }
      }
    ]
  })
}

# Outputs
output "aurora_mysql_endpoint" {
  description = "Aurora MySQL cluster endpoint"
  value       = module.aurora_mysql.cluster_endpoint
}

output "aurora_mysql_reader_endpoint" {
  description = "Aurora MySQL reader endpoint"
  value       = module.aurora_mysql.cluster_reader_endpoint
}

output "aurora_postgresql_endpoint" {
  description = "Aurora PostgreSQL cluster endpoint"
  value       = module.aurora_postgresql.cluster_endpoint
}

output "aurora_postgresql_reader_endpoint" {
  description = "Aurora PostgreSQL reader endpoint"
  value       = module.aurora_postgresql.cluster_reader_endpoint
}

output "monitoring_asg_name" {
  description = "Name of the monitoring Auto Scaling Group"
  value       = aws_autoscaling_group.monitoring.name
}

output "database_config_parameter" {
  description = "SSM parameter containing database configuration"
  value       = aws_ssm_parameter.database_config.name
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.monitoring.dashboard_name}"
}

output "environment_summary" {
  description = "Production environment configuration summary"
  value = {
    environment = var.environment
    region      = var.aws_region
    vpc_id      = module.vpc.vpc_id
    databases   = {
      mysql = {
        type             = "aurora"
        cluster_id       = module.aurora_mysql.cluster_id
        writer_endpoint  = module.aurora_mysql.cluster_endpoint
        reader_endpoint  = module.aurora_mysql.cluster_reader_endpoint
        instance_count   = length(module.aurora_mysql.instance_ids)
      }
      postgresql = {
        type             = "aurora"
        cluster_id       = module.aurora_postgresql.cluster_id
        writer_endpoint  = module.aurora_postgresql.cluster_endpoint
        reader_endpoint  = module.aurora_postgresql.cluster_reader_endpoint
        instance_count   = length(module.aurora_postgresql.instance_ids)
      }
    }
    monitoring = {
      asg_name         = aws_autoscaling_group.monitoring.name
      min_instances    = aws_autoscaling_group.monitoring.min_size
      max_instances    = aws_autoscaling_group.monitoring.max_size
      current_capacity = aws_autoscaling_group.monitoring.desired_capacity
    }
  }
}