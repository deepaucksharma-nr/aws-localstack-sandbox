variable "use_localstack" {
  default = true
}

variable "localstack_endpoint" {
  default = "http://localhost:4566"
}

# Test security group
resource "aws_security_group" "test" {
  name        = "test-sg"
  description = "Test security group for LocalStack"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }
}

output "test_sg_id" {
  value = aws_security_group.test.id
}
