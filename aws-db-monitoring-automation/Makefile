.PHONY: help test start stop clean deploy

help:
	@echo "Usage:"
	@echo "  make start    - Start test environment"
	@echo "  make stop     - Stop test environment"
	@echo "  make test     - Run tests"
	@echo "  make clean    - Clean everything"
	@echo "  make deploy   - Deploy to AWS"

start:
	docker-compose up -d
	@echo "Waiting for services..."
	@sleep 30
	@echo "Ready: MySQL on 3306, PostgreSQL on 5432, LocalStack on 4566"

stop:
	docker-compose down -v

test: start
	@echo "Running tests inside container..."
	docker-compose run --rm test-runner /usr/local/bin/run-tests.sh all
	@make stop

test-unit:
	cd test && python3 -m pytest unit/ -v

clean:
	rm -rf test-results/ coverage/ .pytest_cache/
	rm -rf terraform/.terraform terraform/*.tfstate*
	docker-compose down -v --remove-orphans

deploy:
	@echo "Deploying to AWS..."
	@echo "Make sure terraform.tfvars and databases.yml are configured"
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	./scripts/deploy-monitoring.sh -k ~/.ssh/your-key.pem

logs:
	docker-compose logs -f

shell:
	docker-compose exec test-runner bash