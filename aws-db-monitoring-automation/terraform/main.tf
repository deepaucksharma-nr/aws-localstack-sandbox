locals {
  vpc_id    = var.use_localstack ? data.aws_ssm_parameter.vpc_id[0].value : var.vpc_id
  subnet_id = var.use_localstack ? data.aws_ssm_parameter.subnet_id[0].value : var.subnet_id
  ami_id    = var.use_localstack ? "ami-12345678" : (var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2[0].id)
  
  # Use pre-created security group for LocalStack
  use_existing_sg = var.use_localstack
  existing_sg_id  = var.use_localstack ? data.aws_ssm_parameter.security_group_id[0].value : null
}

data "aws_ami" "amazon_linux_2" {
  count       = var.ami_id == "" ? 1 : 0
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

# Generate unique suffix if unique_identifier is provided
locals {
  name_suffix = var.unique_identifier != "" ? "-${var.unique_identifier}" : ""
}

resource "aws_security_group" "monitoring" {
  count       = local.use_existing_sg ? 0 : 1
  name        = "${var.monitoring_server_name}${local.name_suffix}-sg"
  description = "Security group for database monitoring server"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_http ? [1] : []
    content {
      description = "HTTP for monitoring UI"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = var.allowed_http_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = var.enable_https ? [1] : []
    content {
      description = "HTTPS for monitoring UI"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.allowed_http_cidr_blocks
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.monitoring_server_name}${local.name_suffix}-sg"
  }
}

# IAM role for monitoring instance
resource "aws_iam_role" "monitoring" {
  name = "${var.monitoring_server_name}${local.name_suffix}-role"

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

  tags = {
    Name = "${var.monitoring_server_name}${local.name_suffix}-role"
  }
}

# IAM policy for accessing secrets and parameters
resource "aws_iam_role_policy" "monitoring_secrets" {
  name = "${var.monitoring_server_name}${local.name_suffix}-secrets-policy"
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
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.monitoring_server_name}/*",
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:rds-db-monitoring/*",
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:newrelic/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:parameter/${var.monitoring_server_name}/*",
          "arn:aws:ssm:${var.aws_region}:*:parameter/rds-db-monitoring/*",
          "arn:aws:ssm:${var.aws_region}:*:parameter/newrelic/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "secretsmanager.${var.aws_region}.amazonaws.com",
              "ssm.${var.aws_region}.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

# Attach CloudWatch policy for monitoring (only for real AWS)
resource "aws_iam_role_policy_attachment" "monitoring_cloudwatch" {
  count      = var.use_localstack ? 0 : 1
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach SSM policy for session manager access (only for real AWS)
resource "aws_iam_role_policy_attachment" "monitoring_ssm" {
  count      = var.use_localstack ? 0 : 1
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile
resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.monitoring_server_name}${local.name_suffix}-profile"
  role = aws_iam_role.monitoring.name
}

resource "aws_instance" "monitoring" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = local.use_existing_sg ? [local.existing_sg_id] : [aws_security_group.monitoring[0].id]
  subnet_id              = local.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = var.monitoring_server_name
    Type = "monitoring"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    
    # Log all output
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
    echo "Starting user data script at $(date)"
    
    # Update system
    echo "Updating system packages..."
    yum update -y || { echo "Failed to update system"; exit 1; }
    
    # Install required packages
    echo "Installing Python and dependencies..."
    yum install -y python3 python3-pip unzip || { echo "Failed to install packages"; exit 1; }
    
    # Install Python packages
    echo "Installing Python packages..."
    pip3 install ansible boto3 || { echo "Failed to install Python packages"; exit 1; }
    
    # Install AWS CLI v2
    echo "Installing AWS CLI v2..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" || { echo "Failed to download AWS CLI"; exit 1; }
    unzip -q awscliv2.zip || { echo "Failed to unzip AWS CLI"; exit 1; }
    ./aws/install || { echo "Failed to install AWS CLI"; exit 1; }
    rm -rf awscliv2.zip aws/
    
    echo "User data script completed successfully at $(date)"
  EOF
}