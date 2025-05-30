-- PostgreSQL Query Performance Monitoring Setup Script
-- Run this script as a superuser on your PostgreSQL databases

-- Create monitoring user if not exists
CREATE USER IF NOT EXISTS newrelic WITH PASSWORD 'CHANGE_ME_SECURE_PASSWORD';

-- Grant basic monitoring permissions
GRANT SELECT ON pg_stat_database TO newrelic;
GRANT SELECT ON pg_stat_database_conflicts TO newrelic;
GRANT SELECT ON pg_stat_bgwriter TO newrelic;

-- Enable pg_stat_statements extension (required for query monitoring)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Grant permissions for query-level monitoring
-- Add newrelic user to pg_read_all_stats role (PostgreSQL 10+)
GRANT pg_read_all_stats TO newrelic;

-- Alternative for PostgreSQL < 10
-- GRANT SELECT ON pg_stat_statements TO newrelic;
-- GRANT SELECT ON pg_stat_statements_info TO newrelic;

-- Grant additional permissions for extended metrics
GRANT SELECT ON pg_stat_user_tables TO newrelic;
GRANT SELECT ON pg_stat_user_indexes TO newrelic;
GRANT SELECT ON pg_statio_user_tables TO newrelic;
GRANT SELECT ON pg_statio_user_indexes TO newrelic;

-- Allow connection to all databases
GRANT CONNECT ON DATABASE postgres TO newrelic;
-- Add similar grants for other databases as needed

-- Verify permissions
SELECT 
    'newrelic' as username,
    rolsuper as is_superuser,
    rolcreaterole as can_create_role,
    rolcreatedb as can_create_db,
    rolcanlogin as can_login,
    rolreplication as is_replication_role
FROM pg_roles 
WHERE rolname = 'newrelic';

-- Verify pg_stat_statements is enabled
SELECT * FROM pg_available_extensions WHERE name = 'pg_stat_statements';