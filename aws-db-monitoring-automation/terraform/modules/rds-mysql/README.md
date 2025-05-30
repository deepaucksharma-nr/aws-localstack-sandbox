# RDS MySQL Terraform Module

This module creates an RDS MySQL instance with support for New Relic monitoring.

## Features

- RDS MySQL instance with configurable parameters
- Automatic password generation and storage in AWS Secrets Manager
- Security group creation with customizable ingress rules
- Enhanced monitoring with CloudWatch
- Performance Insights support
- Automated New Relic user creation with proper permissions
- Query performance monitoring enabled by default

## Usage

```hcl
module "mysql_rds" {
  source = "../../modules/rds-mysql"

  identifier = "myapp-mysql"
  
  # Database configuration
  engine_version    = "8.0.35"
  instance_class    = "db.t3.small"
  allocated_storage = 100
  storage_type      = "gp3"
  
  # Network configuration
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.database_subnets
  
  # Security
  allowed_cidr_blocks = ["10.0.0.0/16"]
  
  # High availability
  multi_az = true
  
  # Backup
  backup_retention_period = 30
  
  # Monitoring
  monitoring_interval          = 60
  performance_insights_enabled = true
  
  # New Relic
  create_newrelic_user = true
  
  tags = {
    Environment = "production"
    Application = "myapp"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| identifier | The name of the RDS instance | `string` | n/a | yes |
| engine_version | The engine version to use for MySQL | `string` | `"8.0"` | no |
| instance_class | The instance type of the RDS instance | `string` | `"db.t3.micro"` | no |
| allocated_storage | The allocated storage in gibibytes | `number` | `20` | no |
| storage_type | Storage type (gp2, gp3, io1) | `string` | `"gp3"` | no |
| storage_encrypted | Specifies whether the DB instance is encrypted | `bool` | `true` | no |
| database_name | The name of the database to create | `string` | `null` | no |
| master_username | Username for the master DB user | `string` | `"admin"` | no |
| master_password | Password for the master DB user | `string` | `null` | no |
| create_random_password | Whether to create a random password | `bool` | `true` | no |
| subnet_ids | List of subnet IDs for the DB subnet group | `list(string)` | n/a | yes |
| vpc_id | VPC ID where the database will be created | `string` | n/a | yes |
| security_group_ids | Additional security group IDs to associate | `list(string)` | `[]` | no |
| create_security_group | Whether to create a security group for RDS | `bool` | `true` | no |
| allowed_cidr_blocks | CIDR blocks allowed to connect to RDS | `list(string)` | `[]` | no |
| multi_az | Specifies if the RDS instance is multi-AZ | `bool` | `false` | no |
| publicly_accessible | Bool to control if instance is publicly accessible | `bool` | `false` | no |
| backup_retention_period | The days to retain backups for | `number` | `7` | no |
| deletion_protection | Database deletion protection | `bool` | `false` | no |
| monitoring_interval | Interval for enhanced monitoring metrics | `number` | `60` | no |
| create_newrelic_user | Whether to create New Relic monitoring user | `bool` | `true` | no |
| tags | A map of tags to assign to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| instance_id | The RDS instance ID |
| endpoint | The connection endpoint |
| address | The hostname of the RDS instance |
| port | The database port |
| master_password_secret_arn | ARN of the secret containing the master password |
| newrelic_password_secret_name | Name of the secret containing the New Relic password |

## New Relic User Permissions

When `create_newrelic_user` is enabled, the module automatically creates a user with these permissions:

```sql
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'newrelic'@'%';
```

For query performance monitoring, the module also ensures:
- Performance Schema is enabled
- Required performance schema consumers are enabled

## Security Considerations

1. **Passwords**: Always use AWS Secrets Manager for password storage
2. **Network**: Use private subnets and restrict security group rules
3. **Encryption**: Storage encryption is enabled by default
4. **Backups**: Configure appropriate retention periods

## Integration with New Relic

After creating the RDS instance, configure New Relic monitoring:

1. Retrieve the New Relic password:
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id "myapp-mysql-newrelic-password" \
     --query SecretString --output text
   ```

2. Update your `databases.yml` configuration:
   ```yaml
   - host: <RDS_ENDPOINT>
     port: 3306
     user: newrelic
     password_source: aws_secrets_manager
     password_key: myapp-mysql-newrelic-password
   ```

3. Deploy the monitoring configuration using the main automation.