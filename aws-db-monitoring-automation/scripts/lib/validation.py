#!/usr/bin/env python3
"""
Comprehensive validation utilities for configuration files
"""

import re
from typing import Dict, List, Any, Tuple
import ipaddress


class ConfigValidator:
    """Validates database configuration"""
    
    def __init__(self):
        self.errors = []
        self.warnings = []
    
    def validate_config(self, config: Dict[str, Any]) -> Tuple[bool, List[str], List[str]]:
        """Validate entire configuration"""
        self.errors = []
        self.warnings = []
        
        # Validate MySQL databases
        mysql_dbs = config.get('mysql_databases', [])
        for i, db in enumerate(mysql_dbs):
            self._validate_database(db, 'mysql', i)
        
        # Validate PostgreSQL databases
        postgres_dbs = config.get('postgresql_databases', [])
        for i, db in enumerate(postgres_dbs):
            self._validate_database(db, 'postgresql', i)
        
        # Check for duplicate service names
        self._check_duplicate_names(config)
        
        return len(self.errors) == 0, self.errors, self.warnings
    
    def _validate_database(self, db: Dict[str, Any], db_type: str, index: int):
        """Validate individual database configuration"""
        prefix = f"{db_type}[{index}]"
        
        # Required fields
        if 'name' not in db:
            self.errors.append(f"{prefix}: Missing required field 'name'")
        elif not self._validate_name(db['name']):
            self.errors.append(f"{prefix}: Invalid name '{db['name']}' - must contain only alphanumeric, dash, underscore")
        
        if 'type' not in db:
            self.errors.append(f"{prefix}: Missing required field 'type'")
        elif db['type'] != db_type:
            self.errors.append(f"{prefix}: Type mismatch - expected '{db_type}', got '{db['type']}'")
        
        # Validate connection
        conn = db.get('connection', {})
        if not conn:
            self.errors.append(f"{prefix}: Missing 'connection' section")
        else:
            self._validate_connection(conn, prefix)
        
        # Validate credentials
        creds = db.get('credentials', {})
        if not creds:
            self.errors.append(f"{prefix}: Missing 'credentials' section")
        else:
            self._validate_credentials(creds, prefix)
        
        # Validate monitoring settings
        monitoring = db.get('monitoring', {})
        if monitoring:
            self._validate_monitoring(monitoring, prefix)
    
    def _validate_connection(self, conn: Dict[str, Any], prefix: str):
        """Validate connection parameters"""
        # Host validation
        hosts = [conn.get('host'), conn.get('endpoint'), conn.get('cluster_endpoint')]
        valid_hosts = [h for h in hosts if h]
        
        if not valid_hosts:
            self.errors.append(f"{prefix}.connection: No host specified")
        elif len(valid_hosts) > 1:
            self.warnings.append(f"{prefix}.connection: Multiple hosts specified, will use first one")
        else:
            host = valid_hosts[0]
            if not self._validate_host(host):
                self.errors.append(f"{prefix}.connection: Invalid host '{host}'")
        
        # Port validation
        port = conn.get('port')
        if port is not None:
            if not isinstance(port, int) or port < 1 or port > 65535:
                self.errors.append(f"{prefix}.connection: Invalid port '{port}' - must be 1-65535")
        
        # SSL validation
        ssl_mode = conn.get('ssl_mode')
        if ssl_mode and ssl_mode not in ['disable', 'require', 'verify-ca', 'verify-full', 'prefer']:
            self.errors.append(f"{prefix}.connection: Invalid ssl_mode '{ssl_mode}'")
    
    def _validate_credentials(self, creds: Dict[str, Any], prefix: str):
        """Validate credentials configuration"""
        # Username validation
        user_source = creds.get('user_source', 'plain')
        if user_source not in ['plain', 'aws_secrets_manager', 'aws_ssm_parameter', 'env_var']:
            self.errors.append(f"{prefix}.credentials: Invalid user_source '{user_source}'")
        
        if user_source == 'plain' and not creds.get('user'):
            self.errors.append(f"{prefix}.credentials: Missing 'user' for plain text source")
        elif user_source == 'env_var' and not creds.get('user_env'):
            self.errors.append(f"{prefix}.credentials: Missing 'user_env' for environment variable source")
        elif user_source in ['aws_secrets_manager', 'aws_ssm_parameter'] and not creds.get('user_key'):
            self.errors.append(f"{prefix}.credentials: Missing 'user_key' for AWS source")
        
        # Password validation
        password_source = creds.get('password_source', 'plain')
        if password_source not in ['plain', 'aws_secrets_manager', 'aws_ssm_parameter', 'env_var']:
            self.errors.append(f"{prefix}.credentials: Invalid password_source '{password_source}'")
        
        if password_source == 'plain':
            if creds.get('password'):
                self.warnings.append(f"{prefix}.credentials: Using plain text password is not recommended")
        elif password_source == 'env_var' and not creds.get('password_env'):
            self.errors.append(f"{prefix}.credentials: Missing 'password_env' for environment variable source")
        elif password_source in ['aws_secrets_manager', 'aws_ssm_parameter'] and not creds.get('password_key'):
            self.errors.append(f"{prefix}.credentials: Missing 'password_key' for AWS source")
        
        # Validate AWS resource names
        if password_source == 'aws_secrets_manager':
            key = creds.get('password_key', '')
            if key and not self._validate_aws_secret_name(key):
                self.errors.append(f"{prefix}.credentials: Invalid secret name '{key}'")
        elif password_source == 'aws_ssm_parameter':
            key = creds.get('password_key', '')
            if key and not self._validate_ssm_parameter_name(key):
                self.errors.append(f"{prefix}.credentials: Invalid SSM parameter name '{key}'")
    
    def _validate_monitoring(self, monitoring: Dict[str, Any], prefix: str):
        """Validate monitoring settings"""
        # Interval validation
        interval = monitoring.get('interval')
        if interval and not self._validate_interval(interval):
            self.errors.append(f"{prefix}.monitoring: Invalid interval '{interval}' - use format like '30s', '5m', '1h'")
        
        # Numeric validations
        numeric_fields = {
            'max_sql_query_length': (1, 10000),
            'max_sample_rate': (0.0, 1.0),
            'query_timeout': (1, 3600)
        }
        
        for field, (min_val, max_val) in numeric_fields.items():
            value = monitoring.get(field)
            if value is not None:
                if isinstance(value, (int, float)):
                    if value < min_val or value > max_val:
                        self.errors.append(f"{prefix}.monitoring: {field} must be between {min_val} and {max_val}")
                else:
                    self.errors.append(f"{prefix}.monitoring: {field} must be a number")
    
    def _check_duplicate_names(self, config: Dict[str, Any]):
        """Check for duplicate service names"""
        all_names = []
        
        for db_list in [config.get('mysql_databases', []), config.get('postgresql_databases', [])]:
            for db in db_list:
                if 'name' in db:
                    all_names.append(db['name'])
        
        duplicates = [name for name in all_names if all_names.count(name) > 1]
        if duplicates:
            unique_dups = list(set(duplicates))
            self.errors.append(f"Duplicate service names found: {', '.join(unique_dups)}")
    
    def _validate_name(self, name: str) -> bool:
        """Validate service name format"""
        return bool(re.match(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*$', name))
    
    def _validate_host(self, host: str) -> bool:
        """Validate hostname or IP address"""
        # Check if it's an IP address
        try:
            ipaddress.ip_address(host)
            return True
        except ValueError:
            pass
        
        # Check if it's a valid hostname
        hostname_regex = r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'
        return bool(re.match(hostname_regex, host))
    
    def _validate_interval(self, interval: str) -> bool:
        """Validate time interval format"""
        return bool(re.match(r'^\d+[smh]$', interval))
    
    def _validate_aws_secret_name(self, name: str) -> bool:
        """Validate AWS Secrets Manager secret name"""
        # AWS secret names can contain alphanumeric, /, _, -, +, =, ., @
        return bool(re.match(r'^[a-zA-Z0-9/_\-+=.@]+$', name))
    
    def _validate_ssm_parameter_name(self, name: str) -> bool:
        """Validate SSM parameter name"""
        # SSM parameter names must start with / and can contain alphanumeric, /, _, -, .
        return bool(re.match(r'^/[a-zA-Z0-9/_\-.]+$', name))


def validate_yaml_config(config: Dict[str, Any]) -> Tuple[bool, List[str], List[str]]:
    """Convenience function to validate a configuration"""
    validator = ConfigValidator()
    return validator.validate_config(config)


if __name__ == "__main__":
    # Test validation
    test_config = {
        "mysql_databases": [{
            "name": "test-db",
            "type": "mysql",
            "connection": {
                "host": "localhost",
                "port": 3306
            },
            "credentials": {
                "user": "root",
                "password": "test"
            }
        }]
    }
    
    valid, errors, warnings = validate_yaml_config(test_config)
    print(f"Valid: {valid}")
    if errors:
        print("Errors:", errors)
    if warnings:
        print("Warnings:", warnings)