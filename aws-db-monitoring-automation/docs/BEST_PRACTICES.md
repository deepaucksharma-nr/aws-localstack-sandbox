# Best Practices

## Security

### Do this
- Use read-only database users
- Store credentials in AWS Secrets Manager
- Enable TLS/SSL for database connections
- Use IAM roles, not access keys
- Restrict security groups to minimum required

### Don't do this
- Don't use root/admin database accounts
- Don't hardcode passwords anywhere
- Don't open database ports to 0.0.0.0/0
- Don't share monitoring credentials

## Performance

### Database setup
```sql
-- MySQL: Enable Performance Schema
SET GLOBAL performance_schema = ON;

-- PostgreSQL: Enable pg_stat_statements
CREATE EXTENSION pg_stat_statements;
shared_preload_libraries = 'pg_stat_statements'
```

### Collection intervals
- Production critical: 30s
- Production standard: 60s
- Development/staging: 300s

### Resource sizing
- 1-20 databases: t3.small
- 20-50 databases: t3.medium
- 50-100 databases: t3.large
- 100+ databases: Multiple instances

## Operations

### Monitoring setup
1. Start with one database
2. Verify data is flowing
3. Add more databases gradually
4. Monitor the monitoring instance itself

### Maintenance
- Update agent monthly
- Rotate credentials quarterly
- Review permissions regularly
- Clean up old logs

### Alerting
Set alerts for:
- Agent down > 5 minutes
- Database unreachable
- High query response time
- Replication lag (if applicable)

## Common mistakes

1. **Too many databases per instance**
   - Symptom: High CPU, delayed metrics
   - Fix: Split across multiple instances

2. **Wrong permissions**
   - Symptom: Missing metrics
   - Fix: Check grants, especially for performance data

3. **Network issues**
   - Symptom: No data at all
   - Fix: Security groups, routing, DNS

4. **Time sync problems**
   - Symptom: Metrics appear in wrong time
   - Fix: Enable NTP/chrony

## Cost optimization

- Use smallest instance that works
- Increase collection intervals for non-critical databases
- Use single instance per region
- Enable auto-recovery instead of redundancy

## Scaling patterns

### By environment
```
Production → monitoring-prod instance
Staging → monitoring-staging instance
Development → monitoring-dev instance
```

### By region
```
us-east-1 → monitoring-us-east instance
eu-west-1 → monitoring-eu-west instance
```

### By database type
```
MySQL databases → monitoring-mysql instance
PostgreSQL databases → monitoring-postgresql instance
```