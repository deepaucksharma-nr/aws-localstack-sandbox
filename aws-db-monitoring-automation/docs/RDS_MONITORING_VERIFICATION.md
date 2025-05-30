# RDS Monitoring Verification Guide

This guide helps you verify that the New Relic Infrastructure agent is correctly collecting and sending RDS database metrics.

## What Data Should Be Collected

### Infrastructure Agent Base Metrics

The agent collects these for the monitoring EC2 instance itself:
- System metrics (CPU, memory, disk, network)
- Process information
- System configuration

### MySQL RDS Metrics (via nri-mysql)

**Basic Metrics** (collected every 30-60s):
- `db.connections` - Current connections
- `db.queriesPerSecond` - Query rate
- `db.slowQueriesPerSecond` - Slow query rate
- `db.innodb.bufferPoolPagesData` - InnoDB buffer pool usage
- `db.innodb.dataReadsPerSecond` - InnoDB read rate
- `db.innodb.dataWritesPerSecond` - InnoDB write rate

**Extended Metrics** (when enabled):
- Thread statistics
- Query cache metrics
- Table lock waits
- Replication lag (if applicable)

**Query Performance Metrics** (when enabled):
- Top queries by execution time
- Query wait events
- Query execution counts
- Index usage statistics

### PostgreSQL RDS Metrics (via nri-postgresql)

**Basic Metrics** (collected every 30-60s):
- `db.connections` - Current connections
- `db.commitsPerSecond` - Transaction commit rate
- `db.rollbacksPerSecond` - Transaction rollback rate
- `db.bufferHitRatio` - Cache hit percentage
- `db.rowsReadPerSecond` - Row read rate
- `db.rowsInsertedPerSecond` - Row insert rate

**Extended Metrics**:
- Table statistics (size, rows, dead tuples)
- Index usage and efficiency
- Lock statistics
- Vacuum and autovacuum metrics

**Query Performance Metrics** (via pg_stat_statements):
- Query execution time statistics
- Query frequency
- I/O timing
- Buffer usage per query

## Verification Steps

### 1. Check Agent Status

SSH to your monitoring instance and verify the agent is running:

```bash
# Check service status
sudo systemctl status newrelic-infra

# Expected output:
# ● newrelic-infra.service - New Relic Infrastructure Agent
#    Loaded: loaded (/etc/systemd/system/newrelic-infra.service; enabled)
#    Active: active (running)
```

### 2. Verify Configuration Files

```bash
# Check main config
sudo cat /etc/newrelic-infra.yml

# Should contain:
# license_key: <your-40-character-key>
# display_name: <your-monitoring-instance-name>

# Check MySQL integration
sudo cat /etc/newrelic-infra/integrations.d/mysql-config.yml

# Check PostgreSQL integration  
sudo cat /etc/newrelic-infra/integrations.d/postgresql-config.yml
```

### 3. Test Database Connectivity

From the monitoring instance:

```bash
# Test MySQL RDS
nc -zv your-rds-mysql.region.rds.amazonaws.com 3306

# Test PostgreSQL RDS
nc -zv your-rds-postgres.region.rds.amazonaws.com 5432
```

### 4. Check Data Collection Logs

Look for successful data collection:

```bash
# View recent logs
sudo journalctl -u newrelic-infra --since "10 minutes ago"

# Look for successful MySQL collections
sudo journalctl -u newrelic-infra -f | grep "com.newrelic.mysql"

# Look for successful PostgreSQL collections
sudo journalctl -u newrelic-infra -f | grep "com.newrelic.postgresql"
```

Expected log entries:
```
INFO com.newrelic.mysql - Integration health check finished with success
INFO com.newrelic.postgresql - Integration health check finished with success
```

### 5. Manual Integration Test

Test integrations manually to diagnose issues:

```bash
# Test MySQL integration
sudo /var/db/newrelic-infra/newrelic-integrations/bin/nri-mysql \
  -hostname your-rds.region.rds.amazonaws.com \
  -port 3306 \
  -username newrelic \
  -password 'your-password' \
  -verbose

# Test PostgreSQL integration
sudo /var/db/newrelic-infra/newrelic-integrations/bin/nri-postgresql \
  -hostname your-rds.region.rds.amazonaws.com \
  -port 5432 \
  -username newrelic \
  -password 'your-password' \
  -database postgres \
  -verbose
```

### 6. Verify Data in New Relic UI

After 5-10 minutes, check these locations in New Relic:

#### Infrastructure View
1. Go to: https://one.newrelic.com/infrastructure
2. Find your monitoring instance
3. Click on it and navigate to "Third-party services"
4. You should see MySQL and PostgreSQL integrations listed

#### Database Entities
1. Go to: https://one.newrelic.com/explorer
2. Filter by "Databases"
3. You should see your RDS instances listed

#### Query Performance
1. Click on a database entity
2. Navigate to "Query analysis" or "Database" tab
3. You should see:
   - Top queries by time consumed
   - Query throughput
   - Wait events (if query monitoring is enabled)

## Common Verification Issues

### Issue: No Data Appearing

**Check 1: License Key**
```bash
sudo grep license_key /etc/newrelic-infra.yml
# Ensure it's your actual 40-character key
```

**Check 2: Network Connectivity**
```bash
# Test outbound HTTPS
curl -I https://infrastructure-api.newrelic.com/

# Test DNS resolution
nslookup your-rds.region.rds.amazonaws.com
```

**Check 3: Integration Errors**
```bash
# Look for errors
sudo journalctl -u newrelic-infra | grep -i error | tail -20
```

### Issue: Missing Query Performance Data

**For MySQL:**
- Verify Performance Schema is enabled in RDS parameter group
- Check user has `SELECT` on `performance_schema.*`

**For PostgreSQL:**
- Verify pg_stat_statements is in shared_preload_libraries
- Check user has been granted pg_read_all_stats role

### Issue: Partial Data

If you see basic metrics but not extended metrics:
1. Check integration configuration for `EXTENDED_METRICS: true`
2. Verify database user permissions
3. Check collection intervals aren't too long

## Expected Data Flow

1. **Every 30-60 seconds** (based on interval):
   - Agent queries RDS instance
   - Collects metrics via SQL queries
   - Formats data as JSON

2. **Data batching**:
   - Agent batches multiple data points
   - Compresses payload
   - Sends via HTTPS POST to New Relic

3. **In New Relic**:
   - Data processed and stored
   - Available in UI within 1-2 minutes
   - Retained based on your data retention policy

## Verification Script

Use the provided verification script for automated checking:

```bash
./scripts/verify-rds-monitoring.sh \
  -i <monitoring-instance-ip> \
  -k ~/.ssh/your-key.pem \
  -c config/databases.yml \
  -v  # verbose mode
```

This will:
- Check agent status
- Verify configurations
- Test RDS connectivity
- Check for recent data collection
- Provide a summary report

## Success Criteria

Your RDS monitoring is working correctly when:

✅ Infrastructure agent is running without errors
✅ Database integrations show "active" status
✅ Can connect to all RDS instances from monitoring instance
✅ No authentication errors in logs
✅ Data appears in New Relic UI within 5-10 minutes
✅ Query performance metrics available (if enabled)
✅ Custom labels appear on database entities
✅ No gaps in metric collection

## Next Steps

Once verified:
1. Set up alerts for critical metrics
2. Create custom dashboards
3. Configure anomaly detection
4. Set up regular verification checks