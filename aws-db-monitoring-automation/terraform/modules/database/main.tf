# Generic Database Module for RDS and Aurora
# Supports both MySQL and PostgreSQL engines

locals {
  is_aurora = var.database_type == "aurora"
  is_mysql  = var.engine == "mysql"
  
  engine_family = local.is_mysql ? "mysql" : "postgres"
  default_port  = local.is_mysql ? 3306 : 5432
  
  engine_version_map = {
    "mysql-rds"        = var.engine_version != "" ? var.engine_version : "8.0"
    "postgres-rds"     = var.engine_version != "" ? var.engine_version : "15"
    "mysql-aurora"     = var.engine_version != "" ? var.engine_version : "8.0.mysql_aurora.3.02.0"
    "postgres-aurora"  = var.engine_version != "" ? var.engine_version : "15.2"
  }
  
  engine_key = "${local.engine_family}-${var.database_type}"
  engine_version = local.engine_version_map[local.engine_key]
}

# RDS Instance (when not Aurora)
resource "aws_db_instance" "this" {
  count = local.is_aurora ? 0 : 1
  
  identifier = var.identifier
  
  engine         = var.engine
  engine_version = local.engine_version
  instance_class = var.instance_class
  
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted
  kms_key_id           = var.kms_key_id
  
  db_name  = var.database_name
  username = var.master_username
  password = var.master_password
  port     = var.port != 0 ? var.port : local.default_port
  
  vpc_security_group_ids = var.security_group_ids
  db_subnet_group_name   = var.db_subnet_group_name
  
  backup_retention_period = var.backup_retention_period
  backup_window          = var.backup_window
  maintenance_window     = var.maintenance_window
  
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier
  
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_role_arn
  
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  
  tags = merge(
    var.tags,
    {
      Name         = var.identifier
      Engine       = var.engine
      DatabaseType = var.database_type
    }
  )
}

# Aurora Cluster (when Aurora)
resource "aws_rds_cluster" "this" {
  count = local.is_aurora ? 1 : 0
  
  cluster_identifier = var.identifier
  
  engine         = local.is_mysql ? "aurora-mysql" : "aurora-postgresql"
  engine_version = local.engine_version
  engine_mode    = var.engine_mode
  
  database_name   = var.database_name
  master_username = var.master_username
  master_password = var.master_password
  port           = var.port != 0 ? var.port : local.default_port
  
  vpc_security_group_ids = var.security_group_ids
  db_subnet_group_name   = var.db_subnet_group_name
  
  backup_retention_period = var.backup_retention_period
  preferred_backup_window = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier
  
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  
  storage_encrypted = var.storage_encrypted
  kms_key_id       = var.kms_key_id
  
  tags = merge(
    var.tags,
    {
      Name         = var.identifier
      Engine       = var.engine
      DatabaseType = var.database_type
    }
  )
}

# Aurora Instances
resource "aws_rds_cluster_instance" "this" {
  count = local.is_aurora ? var.instance_count : 0
  
  identifier         = "${var.identifier}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this[0].id
  
  instance_class = var.instance_class
  engine         = aws_rds_cluster.this[0].engine
  engine_version = aws_rds_cluster.this[0].engine_version
  
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_role_arn
  
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  
  tags = merge(
    var.tags,
    {
      Name         = "${var.identifier}-${count.index + 1}"
      ClusterRole  = count.index == 0 ? "writer" : "reader"
    }
  )
}

# Outputs
output "endpoint" {
  description = "The connection endpoint"
  value = local.is_aurora ? aws_rds_cluster.this[0].endpoint : aws_db_instance.this[0].endpoint
}

output "reader_endpoint" {
  description = "The reader endpoint (Aurora only)"
  value = local.is_aurora ? aws_rds_cluster.this[0].reader_endpoint : ""
}

output "port" {
  description = "The database port"
  value = local.is_aurora ? aws_rds_cluster.this[0].port : aws_db_instance.this[0].port
}

output "database_name" {
  description = "The database name"
  value = var.database_name
}

output "master_username" {
  description = "The master username"
  value = var.master_username
  sensitive = true
}