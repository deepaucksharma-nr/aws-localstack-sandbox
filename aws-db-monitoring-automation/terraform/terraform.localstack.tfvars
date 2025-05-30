# LocalStack testing configuration
aws_region              = "us-east-1"
instance_type           = "t3.micro"
key_name               = "test-key"
vpc_id                 = "vpc-test123"      # Will be overridden by LocalStack
subnet_id              = "subnet-test123"   # Will be overridden by LocalStack
monitoring_server_name = "test-monitoring-server"
allowed_ssh_cidr_blocks = ["0.0.0.0/0"]

# New Relic test credentials
newrelic_license_key   = "test_license_key_123"
newrelic_account_id    = "test_account_123"
newrelic_region        = "US"

# LocalStack specific
use_localstack      = true
localstack_endpoint = "http://localhost:4566"