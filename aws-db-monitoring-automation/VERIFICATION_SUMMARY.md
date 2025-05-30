# New Relic Infrastructure Agent - RDS Monitoring Verification Summary

## What We've Set Up for Verification

### 1. **Verification Scripts**
- `scripts/verify-rds-monitoring.sh` - Comprehensive RDS monitoring verification
- `scripts/validate-query-monitoring.sh` - Query performance validation
- `scripts/test-db-connection.sh` - Database connectivity testing

### 2. **Test Configurations**
- `config/databases-rds-test.yml` - Sample RDS configuration with:
  - Aurora MySQL cluster endpoints
  - Aurora PostgreSQL instances
  - RDS standard instances
  - Query monitoring enabled
  - Custom labels for organization

### 3. **Data Collection Points**

The Infrastructure agent collects and sends the following to New Relic:

#### System Metrics (from EC2 monitoring instance)
```json
{
  "event_type": "SystemSample",
  "entityKey": "instance-id",
  "cpuPercent": 15.2,
  "memoryUsedPercent": 45.8,
  "diskUsedPercent": 23.4
}
```

#### MySQL RDS Metrics
```json
{
  "event_type": "MysqlSample",
  "entityKey": "myapp-prod.cluster-xxxxx.us-east-1.rds.amazonaws.com:3306",
  "db.connections": 152,
  "db.queriesPerSecond": 1250.5,
  "db.slowQueriesPerSecond": 0.2,
  "db.innodb.bufferPoolPagesData": 65432,
  "service_name": "rds-mysql-prod",
  "db_engine": "aurora-mysql"
}
```

#### PostgreSQL RDS Metrics
```json
{
  "event_type": "PostgresqlSample",
  "entityKey": "analytics-prod.cluster-xxxxx.us-east-1.rds.amazonaws.com:5432",
  "db.connections": 87,
  "db.commitsPerSecond": 342.7,
  "db.cacheHitRatio": 99.2,
  "db.deadlocksPerSecond": 0,
  "service_name": "rds-postgres-analytics",
  "db_engine": "aurora-postgresql"
}
```

#### Query Performance Metrics (when enabled)
```json
{
  "event_type": "MysqlCustomQuerySample",
  "query_text_sample": "SELECT * FROM orders WHERE...",
  "total_time_ms": 1234.5,
  "calls": 450,
  "avg_time_ms": 2.74,
  "rows_examined": 15000
}
```

## How to Verify Data Collection

### Step 1: Deploy Infrastructure
```bash
# Deploy with actual AWS credentials
./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem
```

### Step 2: Wait for Data Collection
- Agent starts collecting immediately after configuration
- First data points appear in New Relic within 1-2 minutes
- Full metrics available after 5-10 minutes

### Step 3: Run Verification
```bash
# From your local machine
./scripts/verify-rds-monitoring.sh \
  -i <monitoring-instance-ip> \
  -k ~/.ssh/your-key.pem \
  -v
```

### Step 4: Check New Relic UI

Navigate to these sections:

1. **Infrastructure Overview**
   - https://one.newrelic.com/infrastructure
   - Find your monitoring instance

2. **Database Entities**
   - https://one.newrelic.com/explorer
   - Filter: Entity type = "Database"
   - Look for your RDS instances

3. **Query Performance**
   - Click on any database entity
   - Navigate to "Query analysis" tab
   - View top queries, wait events

4. **Custom Dashboards**
   - Create dashboard with NRQL queries
   - Monitor specific RDS metrics

## What Success Looks Like

✅ **Agent Status**
```bash
● newrelic-infra.service - New Relic Infrastructure Agent
   Active: active (running) since...
```

✅ **Integration Logs**
```
INFO com.newrelic.mysql - Integration health check finished with success
INFO com.newrelic.postgresql - Integration health check finished with success
```

✅ **Data in New Relic**
- Infrastructure host appears with integrations
- Database entities created for each RDS instance
- Metrics updating every 30-60 seconds
- Query performance data (if enabled)

✅ **No Errors**
- No authentication failures
- No connection timeouts
- No missing metrics

## Common Verification Commands

```bash
# Check agent version
sudo /usr/bin/newrelic-infra --version

# View integration status
sudo newrelic-infra-ctl

# Test MySQL RDS manually
sudo /var/db/newrelic-infra/newrelic-integrations/bin/nri-mysql \
  -hostname your-rds.region.rds.amazonaws.com \
  -username newrelic \
  -password 'password' \
  -verbose

# Check data being sent
sudo tcpdump -i any -s 0 -A 'port 443 and host infrastructure-api.newrelic.com'
```

## Verification Checklist

- [ ] Infrastructure agent installed and running
- [ ] Database integration packages installed (nri-mysql, nri-postgresql)
- [ ] Configuration files created with correct RDS endpoints
- [ ] Security groups allow monitoring instance → RDS communication
- [ ] Database users created with proper permissions
- [ ] SSL/TLS configured for secure connections
- [ ] Query monitoring enabled (Performance Schema/pg_stat_statements)
- [ ] Data appearing in New Relic UI
- [ ] No errors in agent logs
- [ ] Metrics updating at configured intervals

## Next Steps After Verification

1. **Set Up Alerts**
   - High connection count
   - Slow query rate increase
   - Replication lag (if applicable)

2. **Create Dashboards**
   - RDS performance overview
   - Query performance trends
   - Database comparison

3. **Optimize Collection**
   - Adjust intervals based on needs
   - Enable/disable specific metrics
   - Add custom queries

4. **Scale Monitoring**
   - Add more RDS instances
   - Deploy additional monitoring instances
   - Implement multi-region monitoring