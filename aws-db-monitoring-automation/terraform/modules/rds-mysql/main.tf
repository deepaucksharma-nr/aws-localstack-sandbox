locals {
  create_security_group = var.create_security_group
  security_group_ids    = local.create_security_group ? concat([aws_security_group.rds[0].id], var.security_group_ids) : var.security_group_ids
}

# Generate random password if requested
resource "random_password" "master" {
  count   = var.create_random_password && var.master_password == null ? 1 : 0
  length  = 16
  special = true
}

# Store password in Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  count                   = var.create_random_password ? 1 : 0
  name                    = "${var.identifier}-master-password"
  recovery_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name = "${var.identifier}-master-password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "db_password" {
  count     = var.create_random_password ? 1 : 0
  secret_id = aws_secretsmanager_secret.db_password[0].id
  secret_string = jsonencode({
    username = var.master_username
    password = var.create_random_password ? random_password.master[0].result : var.master_password
    engine   = "mysql"
    host     = aws_db_instance.mysql.endpoint
    port     = aws_db_instance.mysql.port
    dbname   = aws_db_instance.mysql.db_name
  })
}

# Create DB subnet group
resource "aws_db_subnet_group" "mysql" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.identifier}-subnet-group"
    }
  )
}

# Create security group if requested
resource "aws_security_group" "rds" {
  count       = local.create_security_group ? 1 : 0
  name        = "${var.identifier}-rds-sg"
  description = "Security group for RDS MySQL instance ${var.identifier}"
  vpc_id      = var.vpc_id

  ingress {
    description = "MySQL from allowed CIDR blocks"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.identifier}-rds-sg"
    }
  )
}

# Create parameter group
resource "aws_db_parameter_group" "mysql" {
  name   = "${var.identifier}-params"
  family = var.parameter_group_family

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  # Default parameters for New Relic monitoring
  parameter {
    name  = "performance_schema"
    value = "1"
  }

  parameter {
    name  = "performance_schema_consumer_events_statements_current"
    value = "ON"
  }

  parameter {
    name  = "performance_schema_consumer_events_statements_history"
    value = "ON"
  }

  parameter {
    name  = "performance_schema_consumer_events_statements_history_long"
    value = "ON"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.identifier}-params"
    }
  )
}

# Create IAM role for enhanced monitoring if requested
resource "aws_iam_role" "enhanced_monitoring" {
  count = var.create_monitoring_role && var.monitoring_interval > 0 ? 1 : 0
  name  = "${var.identifier}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.identifier}-rds-monitoring-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count      = var.create_monitoring_role && var.monitoring_interval > 0 ? 1 : 0
  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Create RDS instance
resource "aws_db_instance" "mysql" {
  identifier = var.identifier

  # Engine
  engine         = "mysql"
  engine_version = var.engine_version

  # Resources
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = var.storage_type
  storage_encrypted = var.storage_encrypted

  # Database
  db_name  = var.database_name
  username = var.master_username
  password = var.create_random_password ? random_password.master[0].result : var.master_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = local.security_group_ids
  publicly_accessible    = var.publicly_accessible
  multi_az               = var.multi_az

  # Backup
  backup_retention_period = var.backup_retention_period
  backup_window           = var.preferred_backup_window
  maintenance_window      = var.preferred_maintenance_window

  # Parameters
  parameter_group_name = aws_db_parameter_group.mysql.name

  # Monitoring
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn             = var.monitoring_interval > 0 ? (var.create_monitoring_role ? aws_iam_role.enhanced_monitoring[0].arn : var.monitoring_role_arn) : null

  # Performance Insights
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  # Deletion protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot

  tags = merge(
    var.tags,
    {
      Name = var.identifier
    }
  )
}

# Create New Relic monitoring user if requested
resource "null_resource" "create_newrelic_user" {
  count = var.create_newrelic_user ? 1 : 0

  triggers = {
    db_instance_id = aws_db_instance.mysql.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for RDS to be available
      aws rds wait db-instance-available --db-instance-identifier ${var.identifier}
      
      # Generate password for New Relic user
      NR_PASSWORD=$(openssl rand -base64 32)
      
      # Create New Relic user
      mysql -h ${aws_db_instance.mysql.address} \
            -P ${aws_db_instance.mysql.port} \
            -u ${var.master_username} \
            -p'${var.create_random_password ? random_password.master[0].result : var.master_password}' \
            -e "CREATE USER IF NOT EXISTS '${var.newrelic_user}'@'%' IDENTIFIED BY '$NR_PASSWORD';"
      
      # Grant necessary permissions
      mysql -h ${aws_db_instance.mysql.address} \
            -P ${aws_db_instance.mysql.port} \
            -u ${var.master_username} \
            -p'${var.create_random_password ? random_password.master[0].result : var.master_password}' \
            -e "GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO '${var.newrelic_user}'@'%';"
      
      # Store New Relic password in Secrets Manager
      aws secretsmanager create-secret \
        --name "${var.identifier}-newrelic-password" \
        --secret-string "$NR_PASSWORD" \
        --tags Key=Name,Value="${var.identifier}-newrelic-password" || \
      aws secretsmanager update-secret \
        --secret-id "${var.identifier}-newrelic-password" \
        --secret-string "$NR_PASSWORD"
    EOT
  }

  depends_on = [aws_db_instance.mysql]
}