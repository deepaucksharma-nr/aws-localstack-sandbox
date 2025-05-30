-- MySQL initialization script for testing
-- Sets up test database with proper permissions for New Relic monitoring

-- Create test databases
CREATE DATABASE IF NOT EXISTS testdb;
CREATE DATABASE IF NOT EXISTS analytics;

-- Create monitoring user with proper permissions
CREATE USER IF NOT EXISTS 'newrelic'@'%' IDENTIFIED BY 'newrelic123';

-- Grant basic monitoring permissions
GRANT SELECT, PROCESS, REPLICATION CLIENT ON *.* TO 'newrelic'@'%';

-- Grant performance schema permissions for query monitoring
GRANT SELECT ON performance_schema.* TO 'newrelic'@'%';
GRANT SELECT ON information_schema.* TO 'newrelic'@'%';
GRANT SELECT ON mysql.user TO 'newrelic'@'%';

-- Note: Performance schema configuration would need to be done after container starts
-- as it requires SUPER privilege which isn't available during init

-- Create test tables
USE testdb;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (email),
    INDEX idx_created (created_at)
);

CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10, 2) NOT NULL,
    status ENUM('pending', 'processing', 'completed', 'cancelled') DEFAULT 'pending',
    FOREIGN KEY (user_id) REFERENCES users(id),
    INDEX idx_user_date (user_id, order_date),
    INDEX idx_status (status)
);

CREATE TABLE IF NOT EXISTS products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INT DEFAULT 0,
    category VARCHAR(50),
    INDEX idx_category (category),
    INDEX idx_price (price)
);

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

-- Create some slow queries for testing
DELIMITER //

CREATE PROCEDURE generate_test_load()
BEGIN
    DECLARE i INT DEFAULT 0;
    WHILE i < 100 DO
        -- Simulate various query patterns
        SELECT COUNT(*) FROM users WHERE created_at > DATE_SUB(NOW(), INTERVAL i DAY);
        SELECT AVG(total_amount) FROM orders WHERE status = 'completed';
        SELECT p.name, COUNT(o.id) as order_count 
        FROM products p 
        LEFT JOIN orders o ON p.id = o.user_id 
        GROUP BY p.name;
        
        SET i = i + 1;
    END WHILE;
END//

DELIMITER ;

-- Analytics database setup
USE analytics;

CREATE TABLE IF NOT EXISTS events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    user_id INT,
    event_data JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_type_time (event_type, created_at)
) ENGINE=InnoDB;

-- Apply privileges
FLUSH PRIVILEGES;

-- Display setup confirmation
SELECT 'MySQL test database initialized successfully!' as status;