.PHONY: help setup test deploy clean localstack-demo validate backup restore

# Default target
help:
	@echo "AWS Database Monitoring Automation - Makefile"
	@echo ""
	@echo "Setup & Configuration:"
	@echo "  make setup              - Install dependencies and prepare environment"
	@echo "  make secrets            - Generate secure secrets for Docker"
	@echo ""
	@echo "Local Development:"
	@echo "  make start              - Start LocalStack and databases"
	@echo "  make stop               - Stop all services"
	@echo "  make localstack-demo    - Run complete LocalStack E2E demo"
	@echo "  make quickstart         - Run quick start script"
	@echo ""
	@echo "Testing:"
	@echo "  make test               - Run all tests"
	@echo "  make test-unit          - Run unit tests only"
	@echo "  make test-integration   - Run integration tests only"
	@echo "  make validate           - Validate configurations and credentials"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy             - Deploy to AWS (requires SSH_KEY_PATH)"
	@echo "  make deploy-dry-run     - Preview deployment changes"
	@echo ""
	@echo "Management:"
	@echo "  make backup             - Create backup of current configuration"
	@echo "  make restore            - Restore from backup (requires BACKUP_FILE)"
	@echo "  make health-check       - Run system health check"
	@echo "  make status             - Show system status"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean              - Clean up all resources"
	@echo "  make clean-local        - Clean up local files only"
	@echo "  make clean-terraform    - Clean up Terraform resources only"

# Setup environment
setup:
	@echo "Setting up environment..."
	@pip3 install -r test/requirements.txt
	@chmod +x scripts/*.sh
	@chmod +x scripts/generate-secrets.sh
	@echo "Setup complete!"

# Generate secrets
secrets:
	@./scripts/generate-secrets.sh

# Start services
start: secrets
	@docker-compose up -d
	@echo "Waiting for services to start..."
	@sleep 10
	@docker-compose ps

# Stop services
stop:
	@docker-compose down

# Run LocalStack demo
localstack-demo: start
	@./scripts/localstack-e2e-demo.sh

# Run quickstart
quickstart: start
	@./quickstart.sh

# Run all tests
test: test-unit test-integration

# Unit tests
test-unit:
	@echo "Running unit tests..."
	@cd test && python -m pytest unit/ -v

# Integration tests
test-integration: start
	@echo "Running integration tests..."
	@./test/run-tests.sh

# Validate configurations
validate:
	@echo "Validating configurations..."
	@if [ -f config/databases.yml ]; then \
		python3 scripts/validate-credentials.py config/databases.yml; \
	else \
		echo "No config/databases.yml found. Using example..."; \
		python3 scripts/validate-credentials.py config/databases.example.yml; \
	fi

# Deploy to AWS
deploy:
	@if [ -z "$(SSH_KEY_PATH)" ]; then \
		echo "ERROR: SSH_KEY_PATH is required. Usage: make deploy SSH_KEY_PATH=~/.ssh/key.pem"; \
		exit 1; \
	fi
	@./scripts/deploy-monitoring.sh -k $(SSH_KEY_PATH) $(DEPLOY_OPTS)

# Deploy dry run
deploy-dry-run:
	@if [ -z "$(SSH_KEY_PATH)" ]; then \
		echo "ERROR: SSH_KEY_PATH is required. Usage: make deploy-dry-run SSH_KEY_PATH=~/.ssh/key.pem"; \
		exit 1; \
	fi
	@./scripts/deploy-monitoring.sh -k $(SSH_KEY_PATH) --dry-run

# Backup configuration
backup:
	@./scripts/lifecycle-manager.sh backup

# Restore from backup
restore:
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "ERROR: BACKUP_FILE is required. Usage: make restore BACKUP_FILE=backups/backup-20240101-120000.tar.gz"; \
		exit 1; \
	fi
	@./scripts/lifecycle-manager.sh restore --file $(BACKUP_FILE)

# Health check
health-check:
	@./scripts/lifecycle-manager.sh health-check

# System status
status:
	@./scripts/lifecycle-manager.sh status

# Clean up all resources
clean:
	@echo "WARNING: This will remove all resources!"
	@./scripts/cleanup-resources.sh --all

# Clean up local files only
clean-local:
	@./scripts/cleanup-resources.sh --local

# Clean up Terraform resources only
clean-terraform:
	@./scripts/cleanup-resources.sh --terraform

# Common variables that can be overridden
DEPLOY_OPTS ?=
SSH_KEY_PATH ?=
BACKUP_FILE ?=