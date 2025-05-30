# Troubleshooting Guide

This guide covers common issues and their solutions when deploying and operating New Relic database monitoring.

## Table of Contents

- [Pre-Deployment Issues](#pre-deployment-issues)
- [Deployment Issues](#deployment-issues)
- [Database Connection Issues](#database-connection-issues)
- [Query Monitoring Issues](#query-monitoring-issues)
- [New Relic Data Issues](#new-relic-data-issues)
- [Performance Issues](#performance-issues)
- [Diagnostic Commands](#diagnostic-commands)

## Pre-Deployment Issues

### Issue: "terraform: command not found"

**Symptom:**
```bash
./scripts/deploy-monitoring.sh: line 123: terraform: command not found
```

**Solution:**
1. Install Terraform:
   ```bash
   # macOS
   brew install terraform
   
   # Linux
   wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
   unzip terraform_1.5.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

2. Verify installation:
   ```bash
   terraform --version
   ```

### Issue: "AWS credentials not configured"

**Symptom:**
```
Error: AWS credentials are not configured
Run: aws configure
```

**Solution:**
1. Configure AWS CLI:
   ```bash
   aws configure
   # Enter your AWS Access Key ID
   # Enter your AWS Secret Access Key
   # Enter your default region
   # Enter output format (json recommended)
   ```

2. Verify credentials:
   ```bash
   aws sts get-caller-identity
   ```

3. For IAM roles:
   ```bash
   export AWS_PROFILE=your-profile-name
   ```

### Issue: "terraform.tfvars contains placeholder values"

**Symptom:**
```
Error: terraform.tfvars contains placeholder values
Please update all YOUR_* values in terraform.tfvars
```

**Solution:**
1. Check for placeholders:
   ```bash
   grep "YOUR_" terraform/terraform.tfvars
   ```

2. Replace all placeholder values with actual values
3. Ensure New Relic license key is valid (40 characters)

## Deployment Issues

### Issue: "Error creating EC2 instance: UnauthorizedOperation"

**Symptom:**
```
Error: Error creating EC2 instance: UnauthorizedOperation: You are not authorized to perform this operation
```

**Solution:**
1. Check IAM permissions. Required permissions:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ec2:RunInstances",
           "ec2:DescribeInstances",
           "ec2:DescribeVpcs",
           "ec2:DescribeSubnets",
           "ec2:DescribeSecurityGroups",
           "ec2:CreateSecurityGroup",
           "ec2:AuthorizeSecurityGroupIngress",
           "ec2:CreateTags"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

2. Verify VPC and subnet exist:
   ```bash
   aws ec2 describe-vpcs --vpc-ids vpc-xxxxx
   aws ec2 describe-subnets --subnet-ids subnet-xxxxx
   ```

### Issue: "SSH key not found in AWS"

**Symptom:**
```
Error: creating EC2 Instance: InvalidKeyPair.NotFound: The key pair 'my-key' does not exist
```

**Solution:**
1. List available key pairs:
   ```bash
   aws ec2 describe-key-pairs --region us-east-1
   ```

2. Create new key pair if needed:
   ```bash
   aws ec2 create-key-pair --key-name my-key --query 'KeyMaterial' --output text > ~/.ssh/my-key.pem
   chmod 600 ~/.ssh/my-key.pem
   ```

3. Update terraform.tfvars with correct key name

### Issue: "Timeout waiting for instance to be ready"

**Symptom:**
```
Timeout waiting for instance to be ready
```

**Solution:**
1. Check instance status in AWS Console
2. Verify security group allows SSH (port 22) from your IP
3. Check instance system log:
   ```bash
   aws ec2 get-console-output --instance-id i-xxxxx
   ```

## Database Connection Issues

### Issue: "Cannot reach port 3306/5432"

**Symptom:**
```
[✗] Cannot reach port 3306 on mysql.example.com
[!] Check security groups and network connectivity
```

**Solution:**
1. Test basic connectivity:
   ```bash
   telnet mysql.example.com 3306
   # or
   nc -zv mysql.example.com 3306
   ```

2. Check database security groups:
   ```bash
   # Find security group
   aws ec2 describe-instances --instance-ids i-xxxxx --query 'Reservations[0].Instances[0].SecurityGroups'
   
   # Check rules
   aws ec2 describe-security-groups --group-ids sg-xxxxx
   ```

3. Add monitoring instance to database security group:
   ```bash
   aws ec2 authorize-security-group-ingress \
     --group-id sg-database \
     --source-group sg-monitoring \
     --protocol tcp \
     --port 3306
   ```

### Issue: "Access denied for user 'newrelic'"

**Symptom:**
```
ERROR 1045 (28000): Access denied for user 'newrelic'@'10.0.1.100' (using password: YES)
```

**Solution:**
1. Verify user exists:
   ```sql
   -- MySQL
   SELECT User, Host FROM mysql.user WHERE User = 'newrelic';
   
   -- PostgreSQL
   \du newrelic
   ```

2. Check user permissions:
   ```sql
   -- MySQL
   SHOW GRANTS FOR 'newrelic'@'%';
   
   -- PostgreSQL
   \l  -- list databases and access privileges
   ```

3. Re-create user with correct permissions:
   ```bash
   # MySQL
   mysql -u root -p < scripts/setup-mysql-monitoring.sql
   
   # PostgreSQL
   psql -U postgres -f scripts/setup-postgresql-monitoring.sql
   ```

### Issue: "SSL/TLS required but not configured"

**Symptom:**
```
FATAL: SSL connection is required
```

**Solution:**
1. For PostgreSQL, update databases.yml:
   ```yaml
   postgresql_databases:
     - host: postgres.example.com
       sslmode: require  # or verify-full for stricter validation
   ```

2. For MySQL, update databases.yml:
   ```yaml
   mysql_databases:
     - host: mysql.example.com
       tls_enabled: true
   ```

## Query Monitoring Issues

### Issue: "pg_stat_statements not found"

**Symptom:**
```
[✗] pg_stat_statements extension is NOT installed
```

**Solution:**
1. Install extension as superuser:
   ```sql
   CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
   ```

2. Add to postgresql.conf:
   ```
   shared_preload_libraries = 'pg_stat_statements'
   pg_stat_statements.max = 10000
   pg_stat_statements.track = all
   ```

3. Restart PostgreSQL:
   ```bash
   sudo systemctl restart postgresql
   ```

### Issue: "Performance Schema is disabled"

**Symptom:**
```
[✗] Performance Schema is NOT enabled. Query monitoring requires performance_schema=ON
```

**Solution:**
1. Check current status:
   ```sql
   SHOW VARIABLES LIKE 'performance_schema';
   ```

2. Enable in my.cnf:
   ```ini
   [mysqld]
   performance_schema = ON
   ```

3. Restart MySQL:
   ```bash
   sudo systemctl restart mysql
   ```

### Issue: "No query data in New Relic"

**Symptom:**
Query performance tab shows no data after 30 minutes

**Solution:**
1. Verify custom query files deployed:
   ```bash
   ssh -i key.pem ec2-user@instance-ip
   ls -la /etc/newrelic-infra/integrations.d/*custom-queries.yml
   ```

2. Check integration logs:
   ```bash
   sudo journalctl -u newrelic-infra -f | grep -E "(mysql|postgresql)"
   ```

3. Manually test query collection:
   ```bash
   # MySQL
   sudo /var/db/newrelic-infra/newrelic-integrations/bin/nri-mysql \
     -hostname mysql.example.com \
     -username newrelic \
     -password 'password' \
     -verbose

   # PostgreSQL
   sudo /var/db/newrelic-infra/newrelic-integrations/bin/nri-postgresql \
     -hostname postgres.example.com \
     -username newrelic \
     -password 'password' \
     -database postgres \
     -verbose
   ```

## New Relic Data Issues

### Issue: "No infrastructure data in New Relic"

**Symptom:**
Monitoring instance not appearing in New Relic after 10 minutes

**Solution:**
1. Check agent status:
   ```bash
   sudo systemctl status newrelic-infra
   ```

2. Verify license key:
   ```bash
   sudo grep license_key /etc/newrelic-infra.yml
   ```

3. Test connectivity to New Relic:
   ```bash
   curl -I https://infrastructure-api.newrelic.com/
   ```

4. Check agent logs:
   ```bash
   sudo journalctl -u newrelic-infra --since "10 minutes ago"
   ```

### Issue: "Database entities not appearing"

**Symptom:**
Infrastructure shows but databases don't appear

**Solution:**
1. Check integration configuration:
   ```bash
   sudo cat /etc/newrelic-infra/integrations.d/mysql-config.yml
   sudo cat /etc/newrelic-infra/integrations.d/postgresql-config.yml
   ```

2. Test database connectivity from monitoring instance:
   ```bash
   ./scripts/test-db-connection.sh \
     --mysql-host mysql.example.com \
     --mysql-pass password \
     --from-instance instance-ip \
     --ssh-key key.pem
   ```

3. Force integration discovery:
   ```bash
   sudo systemctl restart newrelic-infra
   ```

## Performance Issues

### Issue: "High CPU usage on monitoring instance"

**Symptom:**
Monitoring instance CPU consistently above 80%

**Solution:**
1. Check number of monitored databases:
   ```bash
   grep -c "host:" /etc/newrelic-infra/integrations.d/*-config.yml
   ```

2. Increase collection intervals in databases.yml:
   ```yaml
   mysql_databases:
     - host: mysql.example.com
       interval: 60s  # Increase from 30s
       query_metrics_interval: 120s  # Increase from 60s
   ```

3. Upgrade instance type:
   ```bash
   # Update terraform.tfvars
   instance_type = "t3.large"  # From t3.medium
   
   # Apply changes
   terraform apply
   ```

### Issue: "Database performance impact"

**Symptom:**
Database showing increased load after enabling monitoring

**Solution:**
1. Reduce query monitoring frequency:
   ```yaml
   enable_query_monitoring: false  # Temporarily disable
   ```

2. Limit collected metrics:
   ```yaml
   postgresql_databases:
     - host: postgres.example.com
       collection_list: '["postgres"]'  # Only specific databases
       collect_bloat_metrics: false
       collect_db_lock_metrics: false
   ```

3. Optimize custom queries:
   - Remove expensive queries from custom query files
   - Add LIMIT clauses where appropriate

## Diagnostic Commands

### Full System Check
```bash
# Run comprehensive diagnostics
./scripts/setup-verification.sh --verbose

# Validate specific database
./scripts/validate-query-monitoring.sh \
  --mysql-host mysql.example.com \
  --mysql-pass password \
  --pg-host postgres.example.com \
  --pg-pass password
```

### Agent Diagnostics
```bash
# Check agent version
sudo /usr/bin/newrelic-infra --version

# Run agent in foreground with debug
sudo /usr/bin/newrelic-infra -verbose

# Check all integrations
sudo ls -la /var/db/newrelic-infra/newrelic-integrations/bin/

# Test specific integration
sudo /var/db/newrelic-infra/newrelic-integrations/bin/nri-mysql --help
```

### Network Diagnostics
```bash
# Test New Relic endpoints
for endpoint in infrastructure-api.newrelic.com metric-api.newrelic.com; do
  echo "Testing $endpoint:"
  curl -I https://$endpoint/
done

# Test database connectivity
for port in 3306 5432; do
  timeout 5 bash -c "echo > /dev/tcp/database.example.com/$port" && echo "Port $port: OK" || echo "Port $port: FAILED"
done
```

## Getting Help

If issues persist after trying these solutions:

1. **Collect diagnostic information:**
   ```bash
   # Create diagnostic bundle
   tar -czf nr-diagnostics.tar.gz \
     /etc/newrelic-infra.yml \
     /etc/newrelic-infra/integrations.d/ \
     /var/log/newrelic-infra/
   ```

2. **Check New Relic status:**
   - https://status.newrelic.com/

3. **Get support:**
   - Community: https://discuss.newrelic.com
   - Support ticket: https://support.newrelic.com
   - Include diagnostic bundle and deployment logs

## Prevention Tips

1. **Always run verification before deployment:**
   ```bash
   ./scripts/setup-verification.sh --step-by-step
   ```

2. **Test in non-production first:**
   - Use LocalStack setup for testing
   - Deploy to dev/staging before production

3. **Monitor the monitoring:**
   - Set up alerts for monitoring instance health
   - Check agent logs regularly
   - Review New Relic's own infrastructure metrics