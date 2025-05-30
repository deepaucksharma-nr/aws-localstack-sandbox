#!/bin/bash
# Test script for RDS endpoint simulation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Function to test database connectivity
test_connection() {
    local db_type=$1
    local host=$2
    local port=$3
    local user=$4
    local password=$5
    local database=$6
    
    print_status "Testing $db_type connection to $host:$port..."
    
    if [[ "$db_type" == "mysql" ]]; then
        if mysql -h "$host" -P "$port" -u "$user" -p"$password" -e "SELECT 1" "$database" &>/dev/null; then
            print_status "✓ MySQL connection successful"
            return 0
        else
            print_error "✗ MySQL connection failed"
            return 1
        fi
    elif [[ "$db_type" == "postgres" ]]; then
        if PGPASSWORD="$password" psql -h "$host" -p "$port" -U "$user" -d "$database" -c "SELECT 1" &>/dev/null; then
            print_status "✓ PostgreSQL connection successful"
            return 0
        else
            print_error "✗ PostgreSQL connection failed"
            return 1
        fi
    fi
}

# Main execution
main() {
    print_status "Starting RDS endpoint simulation tests..."
    
    # Check if we're in the right directory
    if [[ ! -f "docker-compose-enhanced.yml" ]]; then
        print_error "Please run this script from the project root directory"
        exit 1
    fi
    
    # Start containers with RDS simulation profile
    print_status "Starting containers with RDS simulation..."
    docker-compose -f docker-compose-enhanced.yml --profile rds-test up -d
    
    # Wait for services to be ready
    print_status "Waiting for services to be ready..."
    sleep 10
    
    # Test container endpoints
    print_status "Testing direct container endpoints..."
    test_connection "mysql" "localhost" "3306" "newrelic" "nr_password123" "testdb"
    test_connection "postgres" "localhost" "5432" "postgres" "rootpassword" "testdb"
    
    # Test simulated RDS endpoints
    print_status "Testing simulated RDS endpoints..."
    test_connection "mysql" "localhost" "13306" "newrelic" "nr_password123" "testdb"
    test_connection "postgres" "localhost" "15432" "postgres" "rootpassword" "testdb"
    
    # Run Python integration tests
    print_status "Running Python integration tests..."
    docker-compose -f docker-compose-enhanced.yml exec -T test-runner bash -c "
        cd /workspace
        export RDS_TEST=1
        python -m pytest test/integration/test_rds_endpoints.py -v
    "
    
    # Test configuration loading
    print_status "Testing configuration loading with different providers..."
    docker-compose -f docker-compose-enhanced.yml exec -T test-runner bash -c "
        cd /workspace
        python scripts/discover-databases.py --help
    "
    
    print_status "All tests completed successfully!"
    
    # Cleanup
    read -p "Do you want to stop the containers? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Stopping containers..."
        docker-compose -f docker-compose-enhanced.yml --profile rds-test down
    fi
}

# Run main function
main "$@"