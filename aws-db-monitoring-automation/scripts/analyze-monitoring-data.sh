#!/bin/bash

# Script to analyze what data is captured and sent by monitoring agents

echo "======================================"
echo "MONITORING DATA ANALYSIS"
echo "======================================"
echo ""

# 1. MySQL Performance Schema Data
echo "1. MySQL PERFORMANCE SCHEMA DATA COLLECTION"
echo "==========================================="
echo ""
echo "The MySQL monitoring agent collects the following data:"
echo ""

cat <<'EOF'
A. Query Performance Metrics (from events_statements_summary_by_digest):
   - Query pattern (normalized SQL)
   - Execution count
   - Average/Min/Max execution time
   - Total time spent
   - Rows examined vs rows sent (efficiency)
   - Temporary tables created
   - Index usage statistics
   - First/Last seen timestamps

B. Table I/O Statistics (from table_io_waits_summary_by_table):
   - Read/Write counts per table
   - Insert/Update/Delete counts
   - Average I/O wait times
   - Total I/O time per table

C. Index Usage (from table_io_waits_summary_by_index_usage):
   - Which indexes are being used
   - Read counts per index
   - Index efficiency metrics

D. Connection Statistics (from accounts):
   - Active connections per user/host
   - Total connections
   - Connection history

E. Wait Events (from events_waits_summary_global_by_event_name):
   - Lock wait times
   - I/O wait times
   - Network wait times

Example data structure sent to New Relic:
{
  "entity": {
    "name": "mysql-server-prod",
    "type": "database",
    "displayName": "Production MySQL"
  },
  "metrics": [
    {
      "name": "mysql.query.execution_count",
      "type": "count",
      "value": 1523,
      "attributes": {
        "query_pattern": "SELECT * FROM `users` WHERE `id` = ?",
        "database": "monitor_test",
        "avg_time_ms": 0.45
      }
    },
    {
      "name": "mysql.table.io.reads",
      "type": "count", 
      "value": 8234,
      "attributes": {
        "table": "users",
        "database": "monitor_test"
      }
    }
  ],
  "inventory": {
    "mysql": {
      "version": "8.0.35",
      "performance_schema": "enabled",
      "query_cache": "disabled"
    }
  }
}
EOF

echo ""
echo ""
echo "2. POSTGRESQL STATISTICS DATA COLLECTION"
echo "========================================"
echo ""
echo "The PostgreSQL monitoring agent collects the following data:"
echo ""

cat <<'EOF'
A. Query Performance (from pg_stat_statements):
   - Query ID and pattern
   - Execution count (calls)
   - Total/Mean/Min/Max execution time
   - Rows returned
   - Buffer hits vs disk reads
   - Temporary file usage
   - Planning time vs execution time

B. Table Statistics (from pg_stat_user_tables):
   - Sequential vs index scans
   - Rows inserted/updated/deleted
   - HOT updates (Heap-Only Tuple updates)
   - Dead rows (bloat)
   - Last vacuum/analyze times

C. Index Statistics (from pg_stat_user_indexes):
   - Index scan counts
   - Rows read vs fetched
   - Index size
   - Index efficiency

D. Database Statistics (from pg_stat_database):
   - Transaction commits/rollbacks
   - Cache hit ratio
   - Temporary files created
   - Deadlock counts
   - Connection counts

E. Table Bloat Estimation:
   - Wasted space per table
   - Bloat ratio
   - Recommendations for vacuum

Example data structure sent to New Relic:
{
  "entity": {
    "name": "postgres-server-prod",
    "type": "database",
    "displayName": "Production PostgreSQL"
  },
  "metrics": [
    {
      "name": "postgres.query.calls",
      "type": "count",
      "value": 892,
      "attributes": {
        "query_pattern": "SELECT * FROM products WHERE category = $1",
        "database": "monitor_test",
        "mean_exec_time": 1.23,
        "cache_hit_ratio": 0.95
      }
    },
    {
      "name": "postgres.table.seq_scan",
      "type": "count",
      "value": 123,
      "attributes": {
        "table": "products",
        "schema": "public",
        "rows_returned": 4567
      }
    }
  ],
  "inventory": {
    "postgresql": {
      "version": "15.5",
      "pg_stat_statements": "enabled",
      "shared_buffers": "256MB"
    }
  }
}
EOF

echo ""
echo ""
echo "3. NEW RELIC INFRASTRUCTURE AGENT DATA"
echo "======================================"
echo ""
echo "The Infrastructure agent additionally collects:"
echo ""

cat <<'EOF'
A. System Metrics:
   - CPU usage per database process
   - Memory usage (RSS, shared, private)
   - Disk I/O rates
   - Network traffic

B. Process Information:
   - Database process list
   - Connection counts
   - Query states (active, idle, waiting)

C. Configuration:
   - Database configuration parameters
   - Runtime settings
   - Extension status

D. Custom Attributes:
   - Environment tags
   - Application metadata
   - Business context
EOF

echo ""
echo ""
echo "4. DATA TRANSMISSION FLOW"
echo "========================"
echo ""

cat <<'EOF'
1. Collection Interval:
   - Metrics: Every 30 seconds (configurable)
   - Query samples: Every 60 seconds
   - Inventory: Every 60 seconds

2. Data Pipeline:
   Database → OHI Integration → Infrastructure Agent → New Relic API

3. Data Format:
   - Compressed JSON payloads
   - Batched for efficiency
   - Encrypted in transit (TLS)

4. API Endpoints:
   - Metrics: POST /v1/infra/metrics
   - Events: POST /v1/infra/events
   - Inventory: POST /v1/infra/inventory

5. Authentication:
   - API Key in header
   - Account ID validation
   - Rate limiting applied
EOF

echo ""
echo ""
echo "5. PRIVACY AND SECURITY"
echo "======================="
echo ""

cat <<'EOF'
Data Sanitization:
- Query parameters are replaced with ? or $N
- No actual data values are sent
- Usernames/passwords are never collected
- Only metadata and statistics are transmitted

Filtering Options:
- Exclude specific databases
- Exclude query patterns
- Redact sensitive table names
- Custom attribute filtering
EOF

echo ""
echo "======================================"
echo "END OF ANALYSIS"
echo "======================================"