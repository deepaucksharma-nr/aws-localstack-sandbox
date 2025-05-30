-- PostgreSQL initialization script for testing
-- Create monitoring user and grant permissions
CREATE USER newrelic WITH PASSWORD 'newrelic123';
GRANT SELECT ON pg_stat_database TO newrelic;
GRANT SELECT ON pg_stat_database_conflicts TO newrelic;
GRANT SELECT ON pg_stat_bgwriter TO newrelic;
GRANT SELECT ON pg_stat_user_tables TO newrelic;
GRANT SELECT ON pg_stat_user_indexes TO newrelic;
GRANT SELECT ON pg_stat_replication TO newrelic;

-- Create test database and schema
CREATE DATABASE app_db;
\c app_db;

-- Grant connect permission
GRANT CONNECT ON DATABASE app_db TO newrelic;

-- Create schema and tables
CREATE SCHEMA IF NOT EXISTS public;

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    stock_quantity INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2),
    status VARCHAR(20) DEFAULT 'pending'
);

CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id),
    product_id INT REFERENCES products(id),
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL
);

-- Create indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);

-- Grant permissions on schema and tables
GRANT USAGE ON SCHEMA public TO newrelic;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO newrelic;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO newrelic;

-- Insert test data
INSERT INTO users (username, email) VALUES
    ('pguser1', 'pguser1@example.com'),
    ('pguser2', 'pguser2@example.com'),
    ('pguser3', 'pguser3@example.com');

INSERT INTO products (name, price, stock_quantity) VALUES
    ('Product A', 29.99, 100),
    ('Product B', 49.99, 50),
    ('Product C', 99.99, 25);

INSERT INTO orders (user_id, total_amount, status) VALUES
    (1, 79.98, 'completed'),
    (2, 149.97, 'processing'),
    (3, 29.99, 'pending');

-- Create function to simulate long-running queries
CREATE OR REPLACE FUNCTION simulate_slow_query()
RETURNS TABLE (result TEXT) AS $$
BEGIN
    PERFORM pg_sleep(2);
    RETURN QUERY
    SELECT 'Slow query completed'::TEXT;
END;
$$ LANGUAGE plpgsql;