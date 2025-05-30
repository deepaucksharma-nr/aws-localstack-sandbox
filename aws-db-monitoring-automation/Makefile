.PHONY: help test test-unit test-integration test-e2e lint clean start stop logs

# Default target
help:
	@echo "AWS Database Monitoring Automation - Make Targets"
	@echo ""
	@echo "Development:"
	@echo "  make start          - Start LocalStack and test environment"
	@echo "  make stop           - Stop all containers"
	@echo "  make logs           - View container logs"
	@echo "  make clean          - Clean up all test artifacts"
	@echo ""
	@echo "Testing:"
	@echo "  make test           - Run all tests"
	@echo "  make test-unit      - Run unit tests only"
	@echo "  make test-integration - Run integration tests only"
	@echo "  make test-e2e       - Run end-to-end tests only"
	@echo "  make lint           - Run all linters"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy-local   - Deploy to LocalStack"
	@echo "  make deploy-aws     - Deploy to AWS (requires configuration)"

# Start test environment
start:
	@echo "Starting test environment..."
	docker-compose up -d
	@echo "Waiting for services to be ready..."
	@sleep 30
	@echo "Test environment is ready!"
	@echo "LocalStack: http://localhost:4566"
	@echo "Mock New Relic API: http://localhost:8080"
	@echo "MySQL: localhost:3306 (user: newrelic, pass: newrelic123)"
	@echo "PostgreSQL: localhost:5432 (user: newrelic, pass: newrelic123)"

# Stop test environment
stop:
	@echo "Stopping test environment..."
	docker-compose down -v
	@echo "Test environment stopped."

# View logs
logs:
	docker-compose logs -f

# Run all tests
test: start
	@echo "Running all tests..."
	docker-compose exec test-runner /usr/local/bin/run-tests.sh all
	@make stop

# Run unit tests
test-unit:
	@echo "Running unit tests..."
	cd test && python3 -m pytest unit/ -v

# Run integration tests
test-integration: start
	@echo "Running integration tests..."
	docker-compose exec test-runner /usr/local/bin/run-tests.sh integration
	@make stop

# Run end-to-end tests
test-e2e: start
	@echo "Running end-to-end tests..."
	docker-compose exec test-runner /usr/local/bin/run-tests.sh e2e
	@make stop

# Run linters
lint:
	@echo "Running linters..."
	@echo "Checking Terraform formatting..."
	cd terraform && terraform fmt -check -recursive || (echo "Run 'make fmt' to fix formatting" && exit 1)
	@echo "Validating Terraform..."
	cd terraform && terraform init -backend=false && terraform validate
	@echo "Linting Ansible..."
	ansible-lint ansible/playbooks/*.yml || true
	@echo "Linting Python..."
	flake8 test/ --max-line-length=120 || true

# Format code
fmt:
	@echo "Formatting Terraform code..."
	cd terraform && terraform fmt -recursive
	@echo "Formatting complete."

# Clean up
clean:
	@echo "Cleaning up..."
	rm -rf test-results/
	rm -rf coverage/
	rm -rf .pytest_cache/
	rm -rf **/__pycache__
	rm -rf terraform/.terraform/
	rm -rf terraform/tfplan
	rm -rf terraform/*.tfstate*
	docker-compose down -v --remove-orphans
	@echo "Cleanup complete."

# Deploy to LocalStack
deploy-local: start
	@echo "Deploying to LocalStack..."
	cd terraform && \
		terraform init && \
		terraform plan -var-file=terraform.localstack.tfvars -out=tfplan && \
		terraform apply tfplan
	@echo "LocalStack deployment complete."

# Deploy to AWS
deploy-aws:
	@echo "Deploying to AWS..."
	@echo "Make sure you have:"
	@echo "1. Updated terraform/terraform.tfvars with your values"
	@echo "2. Updated config/databases.yml with your database details"
	@echo "3. AWS credentials configured"
	@echo ""
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem

# Initialize project
init:
	@echo "Initializing project..."
	pip3 install -r test/requirements.txt
	cd terraform && terraform init
	npm install -g markdownlint-cli
	@echo "Project initialized."

# Validate configuration
validate:
	@echo "Validating configuration..."
	@test -f config/databases.yml || (echo "ERROR: config/databases.yml not found" && exit 1)
	@test -f terraform/terraform.tfvars || (echo "ERROR: terraform/terraform.tfvars not found" && exit 1)
	@echo "Configuration valid."

# Run security scan
security:
	@echo "Running security scans..."
	trivy fs . || true
	checkov -d terraform/ || true
	@echo "Security scan complete."