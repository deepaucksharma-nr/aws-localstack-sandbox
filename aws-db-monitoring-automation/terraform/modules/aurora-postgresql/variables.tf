variable "cluster_identifier" {
  description = "The cluster identifier"
  type        = string
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "engine_mode" {
  description = "The database engine mode (provisioned or serverless)"
  type        = string
  default     = "provisioned"
}

variable "instance_class" {
  description = "Instance class for Aurora instances"
  type        = string
  default     = "db.r6g.large"
}

variable "instances" {
  description = "Number of instances in the cluster"
  type        = number
  default     = 2
}

variable "database_name" {
  description = "Name for an automatically created database"
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
  description = "Whether to create a random password"
  type        = bool
  default     = true
}

variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "security_group_ids" {
  description = "List of security group IDs to associate"
  type        = list(string)
  default     = []
}

variable "create_security_group" {
  description = "Whether to create a security group"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to connect"
  type        = list(string)
  default     = []
}

variable "backup_retention_period" {
  description = "Days to retain backups"
  type        = number
  default     = 7
}

variable "preferred_backup_window" {
  description = "Daily backup window"
  type        = string
  default     = "03:00-06:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Database deletion protection"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on deletion"
  type        = bool
  default     = true
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Set of log types to enable"
  type        = list(string)
  default     = ["postgresql"]
}

variable "apply_immediately" {
  description = "Apply changes immediately"
  type        = bool
  default     = false
}

variable "enable_http_endpoint" {
  description = "Enable HTTP endpoint (data API)"
  type        = bool
  default     = false
}

variable "storage_encrypted" {
  description = "Specifies whether the DB cluster is encrypted"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "ARN for the KMS encryption key"
  type        = string
  default     = null
}

variable "parameter_group_family" {
  description = "DB parameter group family"
  type        = string
  default     = "aurora-postgresql15"
}

variable "cluster_parameters" {
  description = "Map of cluster parameters to apply"
  type        = map(string)
  default     = {}
}

variable "instance_parameters" {
  description = "Map of instance parameters to apply"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Map of tags to assign"
  type        = map(string)
  default     = {}
}

variable "newrelic_user" {
  description = "Username for New Relic monitoring"
  type        = string
  default     = "newrelic"
}

variable "create_newrelic_user" {
  description = "Whether to create New Relic monitoring user"
  type        = bool
  default     = true
}

variable "enable_pg_stat_statements" {
  description = "Whether to enable pg_stat_statements extension"
  type        = bool
  default     = true
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

variable "enable_global_cluster" {
  description = "Enable Aurora global cluster"
  type        = bool
  default     = false
}

variable "global_cluster_identifier" {
  description = "Global cluster identifier"
  type        = string
  default     = null
}

variable "serverlessv2_scaling_configuration" {
  description = "Serverless v2 scaling configuration"
  type = object({
    max_capacity = number
    min_capacity = number
  })
  default = null
}