#!/usr/bin/env bash
# Unified Test Runner for AWS DB Monitoring Automation
# Consolidates all testing functionality

set -euo pipefail

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common functions
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Test configuration
TEST_TYPE="${1:-all}"
TEST_RESULTS_DIR="${PROJECT_ROOT}/test-results"
COVERAGE_DIR="${PROJECT_ROOT}/coverage"

# Create directories if they don't exist
mkdir -p "$TEST_RESULTS_DIR" "$COVERAGE_DIR"

# Show help
show_help() {
    cat << EOF
Unified Test Runner

Usage: $(basename "$0") [TEST_TYPE] [OPTIONS]

Test Types:
    unit        Run unit tests
    integration Run integration tests
    e2e         Run end-to-end tests
    smoke       Run smoke tests
    all         Run all tests (default)
    report      Generate test report

Options:
    --verbose   Enable verbose output
    --coverage  Generate coverage report
    --docker    Run tests in Docker container
    --cleanup   Clean up test artifacts after run

Examples:
    $(basename "$0") unit
    $(basename "$0") integration --verbose
    $(basename "$0") all --coverage
    $(basename "$0") report
EOF
}

# Parse options
VERBOSE=false
COVERAGE=false
USE_DOCKER=false
CLEANUP=false

shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --coverage)
            COVERAGE=true
            shift
            ;;
        --docker)
            USE_DOCKER=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Unit tests
run_unit_tests() {
    print_status "Running unit tests..."
    
    cd "$PROJECT_ROOT"
    
    if [ "$COVERAGE" = true ]; then
        pytest test/unit/ -v --cov=scripts --cov=test --cov-report=html:coverage/html --cov-report=xml:coverage/coverage.xml --junit-xml="$TEST_RESULTS_DIR/unit-results.xml"
    else
        pytest test/unit/ -v --junit-xml="$TEST_RESULTS_DIR/unit-results.xml"
    fi
    
    print_success "Unit tests completed"
}

# Integration tests
run_integration_tests() {
    print_status "Running integration tests..."
    
    cd "$PROJECT_ROOT"
    
    # Start test environment if not using Docker
    if [ "$USE_DOCKER" = false ]; then
        print_status "Starting test environment..."
        docker-compose -f docker-compose.dev.yml up -d
        sleep 30
    fi
    
    pytest test/integration/ -v --junit-xml="$TEST_RESULTS_DIR/integration-results.xml"
    
    print_success "Integration tests completed"
}

# End-to-end tests
run_e2e_tests() {
    print_status "Running end-to-end tests..."
    
    cd "$PROJECT_ROOT"
    
    # Run E2E test script
    if [ -f "test/integration/test_e2e_flow.py" ]; then
        pytest test/integration/test_e2e_flow.py -v --junit-xml="$TEST_RESULTS_DIR/e2e-results.xml"
    fi
    
    # Run shell-based E2E tests
    if [ -f "test/e2e-rds-monitoring-test.sh" ]; then
        ./test/e2e-rds-monitoring-test.sh > "$TEST_RESULTS_DIR/e2e-shell.log" 2>&1 || true
    fi
    
    print_success "End-to-end tests completed"
}

# Smoke tests
run_smoke_tests() {
    print_status "Running smoke tests..."
    
    cd "$PROJECT_ROOT"
    
    # Quick validation tests
    print_status "Checking script executability..."
    find scripts -name "*.sh" -type f | while read script; do
        if [ -x "$script" ]; then
            print_check_success "$script is executable"
        else
            print_check_fail "$script is not executable"
        fi
    done
    
    # Check Python syntax
    print_status "Checking Python syntax..."
    find . -name "*.py" -type f | grep -v "__pycache__" | while read pyfile; do
        if python3 -m py_compile "$pyfile" 2>/dev/null; then
            [ "$VERBOSE" = true ] && print_check_success "$pyfile syntax OK"
        else
            print_check_fail "$pyfile has syntax errors"
        fi
    done
    
    # Check YAML files
    print_status "Checking YAML syntax..."
    find . -name "*.yml" -o -name "*.yaml" | grep -v node_modules | while read yamlfile; do
        if python3 -c "import yaml; yaml.safe_load(open('$yamlfile'))" 2>/dev/null; then
            [ "$VERBOSE" = true ] && print_check_success "$yamlfile is valid"
        else
            print_check_fail "$yamlfile is invalid"
        fi
    done
    
    print_success "Smoke tests completed"
}

# Generate test report
generate_report() {
    print_status "Generating test report..."
    
    local report_file="$TEST_RESULTS_DIR/test-report.txt"
    
    {
        echo "AWS DB Monitoring Automation - Test Report"
        echo "=========================================="
        echo "Generated: $(date)"
        echo ""
        
        # Unit test results
        if [ -f "$TEST_RESULTS_DIR/unit-results.xml" ]; then
            echo "Unit Tests:"
            python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('$TEST_RESULTS_DIR/unit-results.xml')
root = tree.getroot()
tests = root.get('tests', '0')
failures = root.get('failures', '0')
errors = root.get('errors', '0')
time = root.get('time', '0')
print(f'  Total: {tests}')
print(f'  Passed: {int(tests) - int(failures) - int(errors)}')
print(f'  Failed: {failures}')
print(f'  Errors: {errors}')
print(f'  Time: {time}s')
" 2>/dev/null || echo "  No results found"
            echo ""
        fi
        
        # Integration test results
        if [ -f "$TEST_RESULTS_DIR/integration-results.xml" ]; then
            echo "Integration Tests:"
            python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('$TEST_RESULTS_DIR/integration-results.xml')
root = tree.getroot()
tests = root.get('tests', '0')
failures = root.get('failures', '0')
errors = root.get('errors', '0')
time = root.get('time', '0')
print(f'  Total: {tests}')
print(f'  Passed: {int(tests) - int(failures) - int(errors)}')
print(f'  Failed: {failures}')
print(f'  Errors: {errors}')
print(f'  Time: {time}s')
" 2>/dev/null || echo "  No results found"
            echo ""
        fi
        
        # Coverage report
        if [ -f "$COVERAGE_DIR/coverage.xml" ]; then
            echo "Code Coverage:"
            python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('$COVERAGE_DIR/coverage.xml')
root = tree.getroot()
coverage = root.get('line-rate', '0')
print(f'  Line Coverage: {float(coverage) * 100:.1f}%')
" 2>/dev/null || echo "  No coverage data found"
            echo ""
        fi
        
    } > "$report_file"
    
    cat "$report_file"
    print_success "Test report saved to: $report_file"
}

# Cleanup
cleanup_test_artifacts() {
    print_status "Cleaning up test artifacts..."
    
    # Stop test containers
    if [ "$USE_DOCKER" = false ]; then
        docker-compose -f docker-compose.dev.yml down -v 2>/dev/null || true
    fi
    
    # Remove temporary files
    find . -name "*.pyc" -delete 2>/dev/null || true
    find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    rm -rf .pytest_cache 2>/dev/null || true
    
    print_success "Cleanup completed"
}

# Main execution
main() {
    print_status "AWS DB Monitoring Automation - Test Runner"
    echo ""
    
    case "$TEST_TYPE" in
        unit)
            run_unit_tests
            ;;
        integration)
            run_integration_tests
            ;;
        e2e)
            run_e2e_tests
            ;;
        smoke)
            run_smoke_tests
            ;;
        all)
            run_smoke_tests
            run_unit_tests
            run_integration_tests
            run_e2e_tests
            ;;
        report)
            generate_report
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown test type: $TEST_TYPE"
            show_help
            exit 1
            ;;
    esac
    
    # Generate report if all tests were run
    if [ "$TEST_TYPE" = "all" ]; then
        generate_report
    fi
    
    # Cleanup if requested
    if [ "$CLEANUP" = true ]; then
        cleanup_test_artifacts
    fi
    
    print_success "Testing completed!"
}

# Run main
main