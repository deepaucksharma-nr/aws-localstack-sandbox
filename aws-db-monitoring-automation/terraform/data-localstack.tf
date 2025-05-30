# Data sources for LocalStack resources
# These will only be used when use_localstack is true

data "aws_ssm_parameter" "vpc_id" {
  count = var.use_localstack ? 1 : 0
  name  = "/localstack/vpc/id"
}

data "aws_ssm_parameter" "subnet_id" {
  count = var.use_localstack ? 1 : 0
  name  = "/localstack/subnet/id"
}

data "aws_ssm_parameter" "security_group_id" {
  count = var.use_localstack ? 1 : 0
  name  = "/localstack/security-group/id"
}

