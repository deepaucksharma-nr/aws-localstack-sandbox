locals {
  port                  = 3306
  create_security_group = var.create_security_group
  security_group_ids    = local.create_security_group ? concat([aws_security_group.aurora[0].id], var.security_group_ids) : var.security_group_ids
  is_serverless_v2      = var.engine_mode == "provisioned" && var.serverlessv2_scaling_configuration != null
}

# Generate random password if requested
resource "random_password" "master" {
  count   = var.create_random_password && var.master_password == null ? 1 : 0
  length  = 16
  special = true
}

# Store password in Secrets Manager
resource "aws_secretsmanager_secret" "cluster_password" {
  count                   = var.create_random_password ? 1 : 0
  name                    = "${var.cluster_identifier}-master-password"
  recovery_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-master-password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "cluster_password" {
  count     = var.create_random_password ? 1 : 0
  secret_id = aws_secretsmanager_secret.cluster_password[0].id
  secret_string = jsonencode({
    username = var.master_username
    password = var.create_random_password ? random_password.master[0].result : var.master_password
    engine   = "mysql"
    host     = aws_rds_cluster.aurora.endpoint
    port     = aws_rds_cluster.aurora.port
    dbname   = aws_rds_cluster.aurora.database_name
  })
}

# Create DB subnet group
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.cluster_identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-subnet-group"
    }
  )
}

# Create security group if requested
resource "aws_security_group" "aurora" {
  count       = local.create_security_group ? 1 : 0
  name        = "${var.cluster_identifier}-aurora-sg"
  description = "Security group for Aurora MySQL cluster ${var.cluster_identifier}"
  vpc_id      = var.vpc_id

  ingress {
    description = "MySQL from allowed CIDR blocks"
    from_port   = local.port
    to_port     = local.port
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
      Name = "${var.cluster_identifier}-aurora-sg"
    }
  )
}

# Create cluster parameter group
resource "aws_rds_cluster_parameter_group" "aurora" {
  name   = "${var.cluster_identifier}-cluster-params"
  family = var.parameter_group_family

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

  # Custom parameters
  dynamic "parameter" {
    for_each = var.cluster_parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-cluster-params"
    }
  )
}

# Create instance parameter group
resource "aws_db_parameter_group" "aurora" {
  name   = "${var.cluster_identifier}-instance-params"
  family = var.parameter_group_family

  dynamic "parameter" {
    for_each = var.instance_parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-instance-params"
    }
  )
}

# Create Aurora cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = var.cluster_identifier

  # Engine configuration
  engine         = "aurora-mysql"
  engine_version = var.engine_version
  engine_mode    = var.engine_mode

  # Database configuration
  database_name   = var.database_name
  master_username = var.master_username
  master_password = var.create_random_password ? random_password.master[0].result : var.master_password

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = local.security_group_ids
  port                   = local.port

  # Parameter groups
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  # Backup configuration
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  backtrack_window             = var.backtrack_window

  # Storage
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.kms_key_id

  # Other settings
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  apply_immediately               = var.apply_immediately
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  enable_http_endpoint            = var.enable_http_endpoint

  # Global cluster
  global_cluster_identifier = var.global_cluster_identifier

  # Serverless v2 scaling
  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverlessv2_scaling_configuration != null ? [var.serverlessv2_scaling_configuration] : []
    content {
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.cluster_identifier
    }
  )
}

# Create cluster instances
resource "aws_rds_cluster_instance" "aurora" {
  count = var.engine_mode == "provisioned" && !local.is_serverless_v2 ? var.instances : 0

  identifier         = "${var.cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id

  instance_class = var.instance_class
  engine         = aws_rds_cluster.aurora.engine
  engine_version = aws_rds_cluster.aurora.engine_version

  db_parameter_group_name = aws_db_parameter_group.aurora.name

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  monitoring_interval = 60
  monitoring_role_arn = var.performance_insights_enabled ? aws_iam_role.enhanced_monitoring[0].arn : null

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-${count.index + 1}"
    }
  )
}

# Create serverless v2 instances
resource "aws_rds_cluster_instance" "aurora_serverless_v2" {
  count = local.is_serverless_v2 ? var.instances : 0

  identifier         = "${var.cluster_identifier}-serverless-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id

  instance_class = "db.serverless"
  engine         = aws_rds_cluster.aurora.engine
  engine_version = aws_rds_cluster.aurora.engine_version

  db_parameter_group_name = aws_db_parameter_group.aurora.name

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_identifier}-serverless-${count.index + 1}"
    }
  )
}

# IAM role for enhanced monitoring
resource "aws_iam_role" "enhanced_monitoring" {
  count = var.performance_insights_enabled ? 1 : 0
  name  = "${var.cluster_identifier}-aurora-monitoring-role"

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
      Name = "${var.cluster_identifier}-aurora-monitoring-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count      = var.performance_insights_enabled ? 1 : 0
  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Create New Relic monitoring user
resource "null_resource" "create_newrelic_user" {
  count = var.create_newrelic_user ? 1 : 0

  triggers = {
    cluster_id = aws_rds_cluster.aurora.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for cluster to be available
      aws rds wait db-cluster-available --db-cluster-identifier ${var.cluster_identifier}
      
      # Generate password for New Relic user
      NR_PASSWORD=$(openssl rand -base64 32)
      
      # Create New Relic user on writer endpoint
      mysql -h ${aws_rds_cluster.aurora.endpoint} \
            -P ${aws_rds_cluster.aurora.port} \
            -u ${var.master_username} \
            -p'${var.create_random_password ? random_password.master[0].result : var.master_password}' \
            -e "CREATE USER IF NOT EXISTS '${var.newrelic_user}'@'%' IDENTIFIED BY '$NR_PASSWORD';"
      
      # Grant necessary permissions
      mysql -h ${aws_rds_cluster.aurora.endpoint} \
            -P ${aws_rds_cluster.aurora.port} \
            -u ${var.master_username} \
            -p'${var.create_random_password ? random_password.master[0].result : var.master_password}' \
            -e "GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO '${var.newrelic_user}'@'%';"
      
      # Grant performance schema access
      mysql -h ${aws_rds_cluster.aurora.endpoint} \
            -P ${aws_rds_cluster.aurora.port} \
            -u ${var.master_username} \
            -p'${var.create_random_password ? random_password.master[0].result : var.master_password}' \
            -e "GRANT SELECT ON performance_schema.* TO '${var.newrelic_user}'@'%';"
      
      # Store New Relic password in Secrets Manager
      aws secretsmanager create-secret \
        --name "${var.cluster_identifier}-newrelic-password" \
        --secret-string "$NR_PASSWORD" \
        --tags Key=Name,Value="${var.cluster_identifier}-newrelic-password" || \
      aws secretsmanager update-secret \
        --secret-id "${var.cluster_identifier}-newrelic-password" \
        --secret-string "$NR_PASSWORD"
    EOT
  }

  depends_on = [
    aws_rds_cluster.aurora,
    aws_rds_cluster_instance.aurora,
    aws_rds_cluster_instance.aurora_serverless_v2
  ]
}