-- PostgreSQL initialization script for testing
-- Sets up test database with proper permissions for New Relic monitoring

-- Create monitoring user
CREATE USER newrelic WITH PASSWORD 'newrelic123';

-- Create test database
CREATE DATABASE testdb;
CREATE DATABASE analytics;

-- Connect to testdb
\c testdb

-- Enable pg_stat_statements extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Grant permissions to monitoring user
GRANT CONNECT ON DATABASE testdb TO newrelic;
GRANT CONNECT ON DATABASE analytics TO newrelic;
GRANT USAGE ON SCHEMA public TO newrelic;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO newrelic;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO newrelic;

-- Grant monitoring-specific permissions
GRANT SELECT ON pg_stat_database TO newrelic;
GRANT SELECT ON pg_stat_database_conflicts TO newrelic;
GRANT SELECT ON pg_stat_bgwriter TO newrelic;
GRANT pg_read_all_stats TO newrelic;  -- PostgreSQL 10+

-- Create test tables
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10, 2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'cancelled'))
);

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INTEGER DEFAULT 0,
    category VARCHAR(50)
);

-- Create indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_created ON users(created_at);
CREATE INDEX idx_orders_user_date ON orders(user_id, order_date);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_products_price ON products(price);

-- Insert test data
INSERT INTO users (username, email) VALUES
    ('testuser1', 'user1@example.com'),
    ('testuser2', 'user2@example.com'),
    ('testuser3', 'user3@example.com');

INSERT INTO products (name, price, stock_quantity, category) VALUES
    ('Product A', 19.99, 100, 'Electronics'),
    ('Product B', 29.99, 50, 'Electronics'),
    ('Product C', 9.99, 200, 'Books'),
    ('Product D', 49.99, 25, 'Electronics');

INSERT INTO orders (user_id, total_amount, status) VALUES
    (1, 49.98, 'completed'),
    (2, 29.99, 'processing'),
    (1, 9.99, 'completed'),
    (3, 69.98, 'pending');

-- Create function for generating test load
CREATE OR REPLACE FUNCTION generate_test_load() RETURNS void AS $$
DECLARE
    i INTEGER := 0;
BEGIN
    WHILE i < 100 LOOP
        -- Simulate various query patterns
        PERFORM COUNT(*) FROM users WHERE created_at > CURRENT_DATE - INTERVAL '1 day' * i;
        PERFORM AVG(total_amount) FROM orders WHERE status = 'completed';
        PERFORM p.name, COUNT(o.id) as order_count 
        FROM products p 
        LEFT JOIN orders o ON p.id = o.user_id 
        GROUP BY p.name;
        
        i := i + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create a table with intentional bloat for testing
CREATE TABLE bloat_test (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert and delete data to create bloat
INSERT INTO bloat_test (data)
SELECT md5(random()::text) FROM generate_series(1, 10000);

DELETE FROM bloat_test WHERE id % 2 = 0;

-- Analytics database setup
\c analytics

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Grant permissions
GRANT CONNECT ON DATABASE analytics TO newrelic;
GRANT USAGE ON SCHEMA public TO newrelic;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO newrelic;

-- Create events table
CREATE TABLE IF NOT EXISTS events (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    user_id INTEGER,
    event_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_events_type_time ON events(event_type, created_at);
CREATE INDEX idx_events_data ON events USING GIN (event_data);

-- Grant future table permissions
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO newrelic;

-- Reset pg_stat_statements to start fresh
SELECT pg_stat_statements_reset();

-- Display setup confirmation
\c postgres
SELECT 'PostgreSQL test database initialized successfully!' as status;