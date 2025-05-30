output "instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.postgresql.id
}

output "instance_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.postgresql.arn
}

output "endpoint" {
  description = "The connection endpoint"
  value       = aws_db_instance.postgresql.endpoint
}

output "address" {
  description = "The hostname of the RDS instance"
  value       = aws_db_instance.postgresql.address
}

output "port" {
  description = "The database port"
  value       = aws_db_instance.postgresql.port
}

output "database_name" {
  description = "The name of the database"
  value       = aws_db_instance.postgresql.db_name
}

output "master_username" {
  description = "The master username for the database"
  value       = aws_db_instance.postgresql.username
}

output "security_group_id" {
  description = "The security group ID of the RDS instance"
  value       = try(aws_security_group.rds[0].id, null)
}

output "db_subnet_group_name" {
  description = "The db subnet group name"
  value       = aws_db_instance.postgresql.db_subnet_group_name
}

output "parameter_group_name" {
  description = "The parameter group name"
  value       = aws_db_instance.postgresql.parameter_group_name
}

output "master_password_secret_arn" {
  description = "The ARN of the secret containing the master password"
  value       = try(aws_secretsmanager_secret.db_password[0].arn, null)
}

output "newrelic_user" {
  description = "The New Relic monitoring username"
  value       = var.create_newrelic_user ? var.newrelic_user : null
}

output "newrelic_password_secret_name" {
  description = "The name of the secret containing the New Relic password"
  value       = var.create_newrelic_user ? "${var.identifier}-newrelic-password" : null
}

output "monitoring_role_arn" {
  description = "The ARN of the monitoring role"
  value       = try(aws_iam_role.enhanced_monitoring[0].arn, var.monitoring_role_arn)
}

output "cloudwatch_log_groups" {
  description = "Map of CloudWatch log groups created for the DB instance"
  value = {
    for log in var.enabled_cloudwatch_logs_exports :
    log => "/aws/rds/instance/${var.identifier}/${log}"
  }
}

output "pg_stat_statements_enabled" {
  description = "Whether pg_stat_statements extension is enabled"
  value       = var.enable_pg_stat_statements
}