terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Dynamic provider configuration based on use_localstack variable
provider "aws" {
  region = var.aws_region

  # LocalStack configuration
  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      ec2            = var.localstack_endpoint
      sts            = var.localstack_endpoint
      iam            = var.localstack_endpoint
      ssm            = var.localstack_endpoint
      secretsmanager = var.localstack_endpoint
      kms            = var.localstack_endpoint
      rds            = var.localstack_endpoint
      cloudwatch     = var.localstack_endpoint
    }
  }

  # Skip validation for LocalStack
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  # LocalStack credentials
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null
}