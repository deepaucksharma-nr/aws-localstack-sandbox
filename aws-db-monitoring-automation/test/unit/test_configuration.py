"""Unit tests for configuration validation"""

import pytest
import yaml
import os
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent


class TestDatabaseConfiguration:
    """Test database configuration validation"""
    
    def test_example_config_exists(self):
        """Test that example configuration file exists"""
        config_path = PROJECT_ROOT / "config" / "databases.example.yml"
        assert config_path.exists(), f"Example config not found at {config_path}"
    
    def test_example_config_valid_yaml(self):
        """Test that example configuration is valid YAML"""
        config_path = PROJECT_ROOT / "config" / "databases.example.yml"
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        
        assert isinstance(config, dict), "Configuration should be a dictionary"
        assert "newrelic_license_key" in config, "Missing newrelic_license_key"
        assert "mysql_databases" in config, "Missing mysql_databases section"
        assert "postgresql_databases" in config, "Missing postgresql_databases section"
    
    def test_mysql_config_structure(self):
        """Test MySQL database configuration structure"""
        config_path = PROJECT_ROOT / "config" / "databases.example.yml"
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        
        mysql_dbs = config.get("mysql_databases", [])
        assert len(mysql_dbs) > 0, "No MySQL databases configured"
        
        for db in mysql_dbs:
            assert "host" in db, "MySQL config missing 'host'"
            assert "user" in db, "MySQL config missing 'user'"
            assert "password" in db, "MySQL config missing 'password'"
            assert "port" in db or db.get("port") == 3306, "MySQL port should be specified or default to 3306"
    
    def test_postgresql_config_structure(self):
        """Test PostgreSQL database configuration structure"""
        config_path = PROJECT_ROOT / "config" / "databases.example.yml"
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        
        pg_dbs = config.get("postgresql_databases", [])
        assert len(pg_dbs) > 0, "No PostgreSQL databases configured"
        
        for db in pg_dbs:
            assert "host" in db, "PostgreSQL config missing 'host'"
            assert "user" in db, "PostgreSQL config missing 'user'"
            assert "password" in db, "PostgreSQL config missing 'password'"
            assert "database" in db, "PostgreSQL config missing 'database'"


class TestTerraformConfiguration:
    """Test Terraform configuration"""
    
    def test_terraform_files_exist(self):
        """Test that required Terraform files exist"""
        terraform_dir = PROJECT_ROOT / "terraform"
        
        required_files = [
            "main.tf",
            "variables.tf",
            "outputs.tf",
            "terraform.tfvars.example",
            "terraform.localstack.tfvars"
        ]
        
        for file in required_files:
            file_path = terraform_dir / file
            assert file_path.exists(), f"Missing Terraform file: {file}"
    
    def test_localstack_configuration(self):
        """Test LocalStack-specific configuration exists"""
        terraform_dir = PROJECT_ROOT / "terraform"
        
        localstack_files = [
            "providers-localstack.tf",
            "data-localstack.tf",
            "terraform.localstack.tfvars"
        ]
        
        for file in localstack_files:
            file_path = terraform_dir / file
            assert file_path.exists(), f"Missing LocalStack file: {file}"


class TestAnsibleConfiguration:
    """Test Ansible configuration"""
    
    def test_ansible_playbook_exists(self):
        """Test that Ansible playbook exists"""
        playbook_path = PROJECT_ROOT / "ansible" / "playbooks" / "install-newrelic.yml"
        assert playbook_path.exists(), f"Ansible playbook not found at {playbook_path}"
    
    def test_ansible_templates_exist(self):
        """Test that Ansible templates exist"""
        template_dir = PROJECT_ROOT / "ansible" / "templates"
        
        required_templates = [
            "newrelic-infra.yml.j2",
            "mysql-config.yml.j2",
            "postgresql-config.yml.j2"
        ]
        
        for template in required_templates:
            template_path = template_dir / template
            assert template_path.exists(), f"Missing Ansible template: {template}"


class TestScripts:
    """Test deployment scripts"""
    
    def test_deployment_script_exists(self):
        """Test that deployment script exists and is executable"""
        script_path = PROJECT_ROOT / "scripts" / "deploy-monitoring.sh"
        assert script_path.exists(), f"Deployment script not found at {script_path}"
        assert os.access(script_path, os.X_OK), "Deployment script is not executable"
    
    def test_deployment_script_has_help(self):
        """Test that deployment script has help option"""
        script_path = PROJECT_ROOT / "scripts" / "deploy-monitoring.sh"
        with open(script_path, 'r') as f:
            content = f.read()
        
        assert "--help" in content, "Deployment script missing --help option"
        assert "usage()" in content, "Deployment script missing usage function"