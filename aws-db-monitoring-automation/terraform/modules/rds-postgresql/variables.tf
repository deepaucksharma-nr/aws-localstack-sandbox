variable "identifier" {
  description = "The name of the RDS instance"
  type        = string
}

variable "engine_version" {
  description = "The engine version to use for PostgreSQL"
  type        = string
  default     = "15"
}

variable "instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "The allocated storage in gibibytes"
  type        = number
  default     = 20
}

variable "storage_type" {
  description = "Storage type (gp2, gp3, io1)"
  type        = string
  default     = "gp3"
}

variable "storage_encrypted" {
  description = "Specifies whether the DB instance is encrypted"
  type        = bool
  default     = true
}

variable "database_name" {
  description = "The name of the database to create when the DB instance is created"
  type        = string
  default     = "postgres"
}

variable "master_username" {
  description = "Username for the master DB user"
  type        = string
  default     = "postgres"
}

variable "master_password" {
  description = "Password for the master DB user"
  type        = string
  sensitive   = true
  default     = null
}

variable "create_random_password" {
  description = "Whether to create a random password for the master user"
  type        = bool
  default     = true
}

variable "subnet_ids" {
  description = "List of subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID where the database will be created"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs to associate with the RDS instance"
  type        = list(string)
  default     = []
}

variable "create_security_group" {
  description = "Whether to create a security group for RDS"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to connect to the RDS instance"
  type        = list(string)
  default     = []
}

variable "multi_az" {
  description = "Specifies if the RDS instance is multi-AZ"
  type        = bool
  default     = false
}

variable "publicly_accessible" {
  description = "Bool to control if instance is publicly accessible"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "The days to retain backups for"
  type        = number
  default     = 7
}

variable "preferred_backup_window" {
  description = "The daily time range during which automated backups are created"
  type        = string
  default     = "03:00-06:00"
}

variable "preferred_maintenance_window" {
  description = "The window to perform maintenance in"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Database deletion protection"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Determines whether a final DB snapshot is created before deletion"
  type        = bool
  default     = true
}

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to enable for exporting to CloudWatch logs"
  type        = list(string)
  default     = ["postgresql"]
}

variable "monitoring_interval" {
  description = "The interval for collecting enhanced monitoring metrics"
  type        = number
  default     = 60
}

variable "monitoring_role_arn" {
  description = "The ARN for the IAM role that permits RDS to send enhanced monitoring metrics to CloudWatch Logs"
  type        = string
  default     = null
}

variable "create_monitoring_role" {
  description = "Whether to create the IAM role for enhanced monitoring"
  type        = bool
  default     = true
}

variable "parameter_group_family" {
  description = "The DB parameter group family"
  type        = string
  default     = "postgres15"
}

variable "parameters" {
  description = "A map of DB parameters to apply"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}

variable "newrelic_user" {
  description = "Username for New Relic monitoring"
  type        = string
  default     = "newrelic"
}

variable "create_newrelic_user" {
  description = "Whether to create a dedicated New Relic monitoring user"
  type        = bool
  default     = true
}

variable "enable_pg_stat_statements" {
  description = "Whether to enable pg_stat_statements extension for query monitoring"
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Specifies whether Performance Insights are enabled"
  type        = bool
  default     = false
}

variable "performance_insights_retention_period" {
  description = "The amount of time in days to retain Performance Insights data"
  type        = number
  default     = 7
}