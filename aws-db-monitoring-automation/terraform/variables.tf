variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the instance will be launched"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where the instance will be launched"
  type        = string
}

variable "monitoring_server_name" {
  description = "Name tag for the monitoring server"
  type        = string
  default     = "db-monitoring-server"
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH into the instance"
  type        = list(string)
  validation {
    condition = alltrue([
      for cidr in var.allowed_ssh_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All values must be valid CIDR blocks."
  }
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance (defaults to latest Amazon Linux 2)"
  type        = string
  default     = ""
}

variable "newrelic_license_key" {
  description = "New Relic license key for agent installation"
  type        = string
  sensitive   = true
}

variable "newrelic_account_id" {
  description = "New Relic account ID"
  type        = string
}

variable "newrelic_region" {
  description = "New Relic region (US or EU)"
  type        = string
  default     = "US"
}

variable "allowed_http_cidr_blocks" {
  description = "CIDR blocks allowed to access HTTP/HTTPS ports"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for cidr in var.allowed_http_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All values must be valid CIDR blocks."
  }
}

variable "enable_https" {
  description = "Enable HTTPS access to monitoring UI"
  type        = bool
  default     = false
}

variable "enable_http" {
  description = "Enable HTTP access to monitoring UI (not recommended for production)"
  type        = bool
  default     = false
}

variable "unique_identifier" {
  description = "Unique identifier to prevent resource naming conflicts"
  type        = string
  default     = ""
}

variable "use_localstack" {
  description = "Whether to use LocalStack for local testing"
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL"
  type        = string
  default     = "http://localhost:4566"
}