output "cluster_id" {
  description = "The RDS Cluster Identifier"
  value       = aws_rds_cluster.aurora.id
}

output "cluster_arn" {
  description = "Amazon Resource Name (ARN) of cluster"
  value       = aws_rds_cluster.aurora.arn
}

output "cluster_endpoint" {
  description = "Writer endpoint for the cluster"
  value       = aws_rds_cluster.aurora.endpoint
}

output "cluster_reader_endpoint" {
  description = "Read-only endpoint for the cluster"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "cluster_port" {
  description = "The database port"
  value       = aws_rds_cluster.aurora.port
}

output "database_name" {
  description = "The database name"
  value       = aws_rds_cluster.aurora.database_name
}

output "master_username" {
  description = "The master username"
  value       = aws_rds_cluster.aurora.master_username
}

output "security_group_id" {
  description = "The security group ID"
  value       = try(aws_security_group.aurora[0].id, null)
}

output "db_subnet_group_name" {
  description = "The db subnet group name"
  value       = aws_rds_cluster.aurora.db_subnet_group_name
}

output "cluster_parameter_group_name" {
  description = "The cluster parameter group name"
  value       = aws_rds_cluster.aurora.db_cluster_parameter_group_name
}

output "instance_parameter_group_name" {
  description = "The instance parameter group name"
  value       = aws_db_parameter_group.aurora.name
}

output "master_password_secret_arn" {
  description = "ARN of the secret containing the master password"
  value       = try(aws_secretsmanager_secret.cluster_password[0].arn, null)
}

output "newrelic_user" {
  description = "The New Relic monitoring username"
  value       = var.create_newrelic_user ? var.newrelic_user : null
}

output "newrelic_password_secret_name" {
  description = "Name of the secret containing the New Relic password"
  value       = var.create_newrelic_user ? "${var.cluster_identifier}-newrelic-password" : null
}

output "instance_ids" {
  description = "List of instance identifiers"
  value = concat(
    aws_rds_cluster_instance.aurora[*].id,
    aws_rds_cluster_instance.aurora_serverless_v2[*].id
  )
}

output "instance_endpoints" {
  description = "List of instance endpoints"
  value = concat(
    aws_rds_cluster_instance.aurora[*].endpoint,
    aws_rds_cluster_instance.aurora_serverless_v2[*].endpoint
  )
}

output "cloudwatch_log_groups" {
  description = "Map of CloudWatch log groups"
  value = {
    for log in var.enabled_cloudwatch_logs_exports :
    log => "/aws/rds/cluster/${var.cluster_identifier}/${log}"
  }
}

output "is_serverless_v2" {
  description = "Whether the cluster is using Serverless v2"
  value       = local.is_serverless_v2
}

output "cluster_members" {
  description = "List of cluster instance identifiers"
  value       = aws_rds_cluster.aurora.cluster_members
}

output "pg_stat_statements_enabled" {
  description = "Whether pg_stat_statements extension is enabled"
  value       = var.enable_pg_stat_statements
}