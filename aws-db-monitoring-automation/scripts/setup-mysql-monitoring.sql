-- MySQL Query Performance Monitoring Setup Script
-- Run this script as root on your MySQL databases

-- Create monitoring user
CREATE USER IF NOT EXISTS 'newrelic'@'%' IDENTIFIED BY 'CHANGE_ME_SECURE_PASSWORD';

-- Grant basic monitoring permissions
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'newrelic'@'%';

-- Grant permissions for performance schema (required for query monitoring)
GRANT SELECT ON performance_schema.* TO 'newrelic'@'%';

-- Grant permissions for information schema
GRANT SELECT ON information_schema.* TO 'newrelic'@'%';

-- Grant permissions for mysql schema (for extended metrics)
GRANT SELECT ON mysql.user TO 'newrelic'@'%';

-- Enable performance schema if not already enabled
-- Note: This requires server restart if not already enabled
-- SET GLOBAL performance_schema = ON;

-- Enable specific performance schema consumers for query monitoring
UPDATE performance_schema.setup_consumers 
SET ENABLED = 'YES' 
WHERE NAME IN (
    'events_statements_current',
    'events_statements_history',
    'events_statements_history_long',
    'events_waits_current',
    'events_waits_history',
    'events_waits_history_long'
);

-- Enable statement instrumentation
UPDATE performance_schema.setup_instruments 
SET ENABLED = 'YES', TIMED = 'YES' 
WHERE NAME LIKE 'statement/%';

-- Enable wait instrumentation for query analysis
UPDATE performance_schema.setup_instruments 
SET ENABLED = 'YES', TIMED = 'YES' 
WHERE NAME LIKE 'wait/io/file/%' 
   OR NAME LIKE 'wait/io/table/%' 
   OR NAME LIKE 'wait/lock/table/%';

-- Verify permissions
SHOW GRANTS FOR 'newrelic'@'%';

-- Verify performance schema is enabled
SHOW VARIABLES LIKE 'performance_schema';

-- Verify statement consumers are enabled
SELECT * FROM performance_schema.setup_consumers 
WHERE NAME LIKE '%statement%';

-- Apply privileges
FLUSH PRIVILEGES;