#!/bin/bash
# Generate monitoring configuration from discovered databases

set -e

# Default values
REGIONS="us-east-1 us-west-2"
CONFIG_DIR="config"
OUTPUT_FILE="${CONFIG_DIR}/databases-discovered.yml"
TAG_FILTER="monitor=newrelic"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --regions)
            REGIONS="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --tag-filter)
            TAG_FILTER="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --regions       Space-separated list of AWS regions (default: us-east-1 us-west-2)"
            echo "  --output        Output file path (default: config/databases-discovered.yml)"
            echo "  --tag-filter    Tag filter in key=value format (default: monitor=newrelic)"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Create config directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "Discovering databases in regions: $REGIONS"
echo "Using tag filter: $TAG_FILTER"

# Run the discovery script
python3 scripts/discover-databases.py \
    --regions $REGIONS \
    --tag-filter "$TAG_FILTER" \
    --output yaml \
    --output-file "$OUTPUT_FILE"

echo "Discovery complete! Configuration saved to: $OUTPUT_FILE"

# Validate the generated configuration
if command -v yamllint &> /dev/null; then
    echo "Validating YAML syntax..."
    yamllint -d relaxed "$OUTPUT_FILE" || true
fi

# Show summary
echo ""
echo "Summary:"
echo "--------"
mysql_count=$(grep -c "provider: rds\|provider: aurora" "$OUTPUT_FILE" | grep -B1 "type: mysql" | wc -l || echo "0")
postgres_count=$(grep -c "provider: rds\|provider: aurora" "$OUTPUT_FILE" | grep -B1 "type: postgresql" | wc -l || echo "0")

echo "MySQL databases found: $mysql_count"
echo "PostgreSQL databases found: $postgres_count"

echo ""
echo "Next steps:"
echo "1. Review the generated configuration in $OUTPUT_FILE"
echo "2. Update database credentials (passwords/secrets)"
echo "3. Run 'terraform apply' to deploy monitoring infrastructure"
echo "4. Run 'ansible-playbook' to configure New Relic monitoring"