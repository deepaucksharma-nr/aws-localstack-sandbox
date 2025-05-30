# LocalStack provider configuration for testing
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = var.aws_region
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2             = var.localstack_endpoint
    sts             = var.localstack_endpoint
    iam             = var.localstack_endpoint
    ssm             = var.localstack_endpoint
    secretsmanager  = var.localstack_endpoint
  }
}

# Variables for LocalStack configuration
variable "localstack_endpoint" {
  description = "LocalStack endpoint URL"
  type        = string
  default     = "http://localhost:4566"
}

variable "use_localstack" {
  description = "Whether to use LocalStack for testing"
  type        = bool
  default     = false
}