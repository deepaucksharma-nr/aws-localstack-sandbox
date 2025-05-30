-- MySQL initialization script for testing
-- Grant permissions to New Relic monitoring user
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'newrelic'@'%';
FLUSH PRIVILEGES;

-- Create test database and tables
CREATE DATABASE IF NOT EXISTS app_db;
USE app_db;

CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_email (email)
);

CREATE TABLE orders (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2),
    status VARCHAR(20) DEFAULT 'pending',
    FOREIGN KEY (user_id) REFERENCES users(id),
    INDEX idx_user_id (user_id),
    INDEX idx_status (status)
);

-- Insert test data
INSERT INTO users (username, email) VALUES
    ('testuser1', 'test1@example.com'),
    ('testuser2', 'test2@example.com'),
    ('testuser3', 'test3@example.com');

INSERT INTO orders (user_id, total_amount, status) VALUES
    (1, 100.50, 'completed'),
    (2, 250.75, 'pending'),
    (1, 75.25, 'completed'),
    (3, 300.00, 'processing');

-- Create some slow queries for testing
DELIMITER //
CREATE PROCEDURE generate_slow_query()
BEGIN
    SELECT SLEEP(2);
    SELECT COUNT(*) FROM users u1 
    CROSS JOIN users u2 
    CROSS JOIN users u3;
END//
DELIMITER ;