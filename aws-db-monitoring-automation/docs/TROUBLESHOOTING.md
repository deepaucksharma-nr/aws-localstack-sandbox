# Troubleshooting

Quick fixes for common problems.

## Nothing showing up in New Relic

```bash
# SSH to your monitoring instance
ssh -i your-key.pem ec2-user@instance-ip

# Check if agent is running
sudo systemctl status newrelic-infra

# If not running, start it
sudo systemctl start newrelic-infra

# Check the logs
sudo journalctl -u newrelic-infra -n 100
```

Common issues:
- Wrong license key - check `/etc/newrelic-infra.yml`
- Can't reach New Relic API - check security groups for outbound HTTPS
- Time sync issues - run `sudo chrony sources`

## Database connection failing

### Can't connect at all

```bash
# From monitoring instance, test connection
nc -zv mysql.example.com 3306

# If that fails, it's network/firewall
# Check security groups - monitoring instance needs access to DB port
```

### Authentication errors

MySQL:
```sql
-- Check user exists and has right host
SELECT user, host FROM mysql.user WHERE user='newrelic';

-- If missing or wrong host
DROP USER IF EXISTS 'newrelic'@'%';
CREATE USER 'newrelic'@'%' IDENTIFIED BY 'password';
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'newrelic'@'%';
```

PostgreSQL:
```sql
-- Check user
\du newrelic

-- Recreate if needed
DROP USER IF EXISTS newrelic;
CREATE USER newrelic WITH PASSWORD 'password';
GRANT pg_monitor TO newrelic;
```

## Query monitoring not working

### PostgreSQL

```bash
# Check if pg_stat_statements is installed
psql -U postgres -c "SELECT * FROM pg_extension WHERE extname = 'pg_stat_statements';"

# If not, install it
psql -U postgres -c "CREATE EXTENSION pg_stat_statements;"

# Also needs this in postgresql.conf:
# shared_preload_libraries = 'pg_stat_statements'
# Then restart PostgreSQL
```

### MySQL

```bash
# Check if Performance Schema is on
mysql -u root -p -e "SHOW VARIABLES LIKE 'performance_schema';"

# If OFF, add to my.cnf:
# [mysqld]
# performance_schema = ON
# Then restart MySQL
```

## High CPU/Memory usage

Too many databases? Increase collection intervals:

```yaml
# databases.yml
mysql_databases:
  - host: mysql.example.com
    interval: 60s  # instead of default 30s
```

Or upgrade the instance:
```hcl
# terraform.tfvars
instance_type = "t3.large"  # from t3.medium
```

## Debugging commands

```bash
# Test specific integration
sudo /var/db/newrelic-infra/newrelic-integrations/bin/nri-mysql \
  -hostname mysql.example.com \
  -username newrelic \
  -password 'password' \
  -verbose

# Check what's being collected
curl -s http://localhost:8081/v1/data | jq .

# Force config reload
sudo systemctl reload newrelic-infra

# Full agent debug mode (temporary)
sudo systemctl stop newrelic-infra
sudo /usr/bin/newrelic-infra -verbose
```

## Still stuck?

1. Collect logs:
   ```bash
   sudo journalctl -u newrelic-infra > /tmp/nr-logs.txt
   cat /etc/newrelic-infra.yml >> /tmp/nr-logs.txt
   cat /etc/newrelic-infra/integrations.d/*.yml >> /tmp/nr-logs.txt
   ```

2. Check status page: https://status.newrelic.com

3. Ask for help: https://discuss.newrelic.com