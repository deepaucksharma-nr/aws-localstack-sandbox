# Generic Database Module Variables

variable "identifier" {
  description = "The name/identifier for the database"
  type        = string
}

variable "database_type" {
  description = "Type of database: rds or aurora"
  type        = string
  validation {
    condition     = contains(["rds", "aurora"], var.database_type)
    error_message = "database_type must be either 'rds' or 'aurora'"
  }
}

variable "engine" {
  description = "Database engine: mysql or postgres"
  type        = string
  validation {
    condition     = contains(["mysql", "postgres"], var.engine)
    error_message = "engine must be either 'mysql' or 'postgres'"
  }
}

variable "engine_version" {
  description = "Engine version (optional - uses sensible defaults)"
  type        = string
  default     = ""
}

variable "engine_mode" {
  description = "Engine mode for Aurora (provisioned, serverless, parallelquery, global)"
  type        = string
  default     = "provisioned"
}

variable "instance_class" {
  description = "Instance class"
  type        = string
}

variable "instance_count" {
  description = "Number of instances (Aurora only)"
  type        = number
  default     = 2
}

variable "allocated_storage" {
  description = "Allocated storage in GB (RDS only)"
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling (RDS only)"
  type        = number
  default     = 1000
}

variable "storage_type" {
  description = "Storage type (RDS only)"
  type        = string
  default     = "gp3"
}

variable "storage_encrypted" {
  description = "Enable storage encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  default     = ""
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
}

variable "master_username" {
  description = "Master username"
  type        = string
  default     = "admin"
}

variable "master_password" {
  description = "Master password"
  type        = string
  sensitive   = true
}

variable "port" {
  description = "Database port (0 = use default)"
  type        = number
  default     = 0
}

variable "vpc_security_group_ids" {
  description = "List of VPC security group IDs"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Alias for vpc_security_group_ids"
  type        = list(string)
  default     = []
}

variable "db_subnet_group_name" {
  description = "DB subnet group name"
  type        = string
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion"
  type        = bool
  default     = false
}

variable "final_snapshot_identifier" {
  description = "Final snapshot identifier"
  type        = string
  default     = ""
}

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch"
  type        = list(string)
  default     = []
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period"
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval"
  type        = number
  default     = 60
}

variable "monitoring_role_arn" {
  description = "Enhanced monitoring IAM role ARN"
  type        = string
  default     = ""
}

variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor version upgrades"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}