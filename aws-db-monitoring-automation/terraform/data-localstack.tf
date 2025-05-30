# Data sources for LocalStack resources
# These will only be used when use_localstack is true

data "aws_ssm_parameter" "vpc_id" {
  count = var.use_localstack ? 1 : 0
  name  = "/test/vpc-id"
}

data "aws_ssm_parameter" "subnet_id" {
  count = var.use_localstack ? 1 : 0
  name  = "/test/subnet-id"
}

# Override VPC and subnet IDs when using LocalStack
locals {
  vpc_id    = var.use_localstack ? data.aws_ssm_parameter.vpc_id[0].value : var.vpc_id
  subnet_id = var.use_localstack ? data.aws_ssm_parameter.subnet_id[0].value : var.subnet_id
}