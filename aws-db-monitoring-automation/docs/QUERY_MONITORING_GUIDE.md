# Query Performance Monitoring Guide

This guide provides detailed information about setting up and using query performance monitoring with New Relic's On-Host Integration (OHI) for MySQL and PostgreSQL.

## Overview

Query performance monitoring provides deep insights into database query execution, helping you:
- Identify slow queries and performance bottlenecks
- Understand query wait events and resource consumption
- Track query execution patterns over time
- Optimize database performance proactively

## Prerequisites

### MySQL Requirements
- MySQL 5.6+ (MySQL 8.0+ recommended for full feature support)
- Performance Schema enabled (`performance_schema = ON`)
- New Relic MySQL integration (nri-mysql)

### PostgreSQL Requirements
- PostgreSQL 9.4+ (PostgreSQL 10+ recommended)
- pg_stat_statements extension installed and configured
- New Relic PostgreSQL integration (nri-postgresql)

## Setup Instructions

### 1. Database Preparation

#### MySQL Setup
```bash
# Run the setup script as MySQL root user
mysql -u root -p < scripts/setup-mysql-monitoring.sql

# Or manually:
CREATE USER 'newrelic'@'%' IDENTIFIED BY 'your_secure_password';
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'newrelic'@'%';
GRANT SELECT ON performance_schema.* TO 'newrelic'@'%';
GRANT SELECT ON information_schema.* TO 'newrelic'@'%';
FLUSH PRIVILEGES;
```

#### PostgreSQL Setup
```bash
# Run the setup script as PostgreSQL superuser
psql -U postgres -f scripts/setup-postgresql-monitoring.sql

# Or manually:
CREATE USER newrelic WITH PASSWORD 'your_secure_password';
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT pg_read_all_stats TO newrelic;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO newrelic;
```

### 2. Configuration

Update your `databases.yml` configuration:

```yaml
# MySQL with query monitoring
mysql_databases:
  - host: mysql.example.com
    port: 3306
    user: newrelic
    password: "secure_password"
    service_name: mysql-production
    # Query monitoring settings
    enable_query_monitoring: true
    query_metrics_interval: 60s
    max_sql_query_length: 1000
    gather_query_samples: true
    extended_metrics: true
    custom_labels:
      environment: production
      application: webapp

# PostgreSQL with query monitoring
postgresql_databases:
  - host: postgres.example.com
    port: 5432
    user: newrelic
    password: "secure_password"
    database: production_db
    service_name: postgres-production
    # Query monitoring settings
    enable_query_monitoring: true
    query_metrics_interval: 60s
    max_sql_query_length: 1000
    collect_bloat_metrics: true
    collect_db_lock_metrics: true
    custom_labels:
      environment: production
      application: webapp
```

### 3. Deployment

Run the deployment script:
```bash
./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem
```

### 4. Validation

Validate the setup using the provided script:
```bash
# Validate MySQL
./scripts/validate-query-monitoring.sh \
  --mysql-host mysql.example.com \
  --mysql-pass your_password

# Validate PostgreSQL
./scripts/validate-query-monitoring.sh \
  --pg-host postgres.example.com \
  --pg-pass your_password \
  --pg-database production_db
```

## Available Metrics

### MySQL Query Metrics
- **Top Queries by Time**: Slowest queries by total execution time
- **Query Digest Analysis**: Normalized queries with statistics
- **Wait Events**: Current wait events across all connections
- **Long Running Queries**: Queries exceeding time thresholds
- **Lock Wait Statistics**: Table-level lock contention metrics
- **Index Usage**: Unused and rarely used indexes

### PostgreSQL Query Metrics
- **pg_stat_statements**: Comprehensive query statistics
- **Query Wait Events**: What queries are waiting for
- **Long Running Queries**: Active queries exceeding thresholds
- **Table Bloat**: Table and index bloat analysis
- **Index Usage Statistics**: Index scan counts and efficiency
- **Lock Monitoring**: Database and table lock metrics

## Customizing Query Collection

### Custom Query Files

You can add custom queries by creating your own query file:

```yaml
# custom-queries.yml
queries:
  - name: my_custom_metric
    run_on:
      - mysql  # or postgresql
    query: |
      SELECT 
        metric_name,
        metric_value
      FROM my_table
    columns:
      - metric_name: varchar
      - metric_value: numeric
```

Reference it in your configuration:
```yaml
mysql_databases:
  - host: mysql.example.com
    custom_metrics_query_file: /path/to/custom-queries.yml
```

### Query Collection Intervals

Adjust collection intervals based on your needs:
- `interval: 30s` - Main metrics collection
- `query_metrics_interval: 60s` - Query-specific metrics

## Troubleshooting

### MySQL Issues

1. **Performance Schema Not Enabled**
   ```sql
   -- Check status
   SHOW VARIABLES LIKE 'performance_schema';
   
   -- Enable in my.cnf
   [mysqld]
   performance_schema = ON
   ```

2. **No Query Data**
   ```sql
   -- Enable consumers
   UPDATE performance_schema.setup_consumers 
   SET ENABLED = 'YES' 
   WHERE NAME LIKE '%statement%';
   ```

### PostgreSQL Issues

1. **pg_stat_statements Not Found**
   ```sql
   -- Install extension
   CREATE EXTENSION pg_stat_statements;
   
   -- Add to postgresql.conf
   shared_preload_libraries = 'pg_stat_statements'
   pg_stat_statements.max = 10000
   pg_stat_statements.track = all
   ```

2. **Permission Denied**
   ```sql
   -- Grant role (PostgreSQL 10+)
   GRANT pg_read_all_stats TO newrelic;
   
   -- Or specific permissions (PostgreSQL < 10)
   GRANT SELECT ON pg_stat_statements TO newrelic;
   ```

## Best Practices

1. **Resource Considerations**
   - Query monitoring adds minimal overhead (typically < 2%)
   - Adjust collection intervals based on database load
   - Monitor pg_stat_statements size in PostgreSQL

2. **Security**
   - Use strong passwords for monitoring users
   - Limit monitoring user permissions to read-only
   - Enable SSL/TLS for database connections

3. **Query Text Handling**
   - Set appropriate `max_sql_query_length` values
   - Be aware that query text may contain sensitive data
   - Consider using query digests instead of full text

## New Relic UI Navigation

1. **Infrastructure > Databases**: Overview of all monitored databases
2. **Database Entity View**: Detailed metrics for specific database
3. **Query Performance Tab**: Query-specific metrics and analysis
4. **Custom Dashboards**: Create dashboards using NRQL queries

### Sample NRQL Queries

```sql
-- Top 10 slowest MySQL queries
SELECT average(total_time_ms) 
FROM MysqlCustomQuerySample 
WHERE query_text_sample IS NOT NULL 
FACET query_text_sample 
LIMIT 10

-- PostgreSQL query wait events
SELECT count(*) 
FROM PostgresqlCustomQuerySample 
WHERE wait_event IS NOT NULL 
FACET wait_event 
TIMESERIES
```

## Additional Resources

- [New Relic PostgreSQL Integration Docs](https://docs.newrelic.com/docs/infrastructure/host-integrations/host-integrations-list/postgresql/postgresql-integration/)
- [New Relic MySQL Integration Docs](https://docs.newrelic.com/install/mysql/)
- [Query-level Monitoring](https://docs.newrelic.com/docs/infrastructure/infrastructure-data/query-level-monitoring/)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review New Relic agent logs: `sudo journalctl -u newrelic-infra -f`
3. Contact New Relic support: https://support.newrelic.com/