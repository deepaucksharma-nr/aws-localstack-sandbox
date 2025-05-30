# LocalStack-specific overrides and workarounds
# This file contains modifications needed for LocalStack Community Edition compatibility

# Get the mock AMI ID from SSM parameter
data "aws_ssm_parameter" "ami_id" {
  count = var.use_localstack ? 1 : 0
  name  = "/test/ami-id"
}

# Create AWS managed policies locally for LocalStack
resource "aws_iam_policy" "cloudwatch_agent_server_localstack" {
  count       = var.use_localstack ? 1 : 0
  name        = "CloudWatchAgentServerPolicy"
  path        = "/aws-service-role/"
  description = "CloudWatch Agent Server Policy for LocalStack"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "ssm_managed_instance_localstack" {
  count       = var.use_localstack ? 1 : 0
  name        = "AmazonSSMManagedInstanceCore"
  path        = "/aws-service-role/"
  description = "SSM Managed Instance Core Policy for LocalStack"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      }
    ]
  })
}

# Override policy attachments for LocalStack
resource "aws_iam_role_policy_attachment" "monitoring_cloudwatch_localstack" {
  count      = var.use_localstack ? 1 : 0
  role       = aws_iam_role.monitoring.name
  policy_arn = aws_iam_policy.cloudwatch_agent_server_localstack[0].arn
}

resource "aws_iam_role_policy_attachment" "monitoring_ssm_localstack" {
  count      = var.use_localstack ? 1 : 0
  role       = aws_iam_role.monitoring.name
  policy_arn = aws_iam_policy.ssm_managed_instance_localstack[0].arn
}

