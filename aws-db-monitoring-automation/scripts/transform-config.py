#!/usr/bin/env python3
"""
Configuration transformation script
Converts SSM JSON format to Ansible YAML format with credential resolution
"""

import json
import yaml
import boto3
import argparse
import sys
import os
from typing import Dict, Any, List, Optional

# Add lib directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), 'lib'))
try:
    from validation import validate_yaml_config
except ImportError:
    # Fallback if validation module not available
    def validate_yaml_config(config):
        return True, [], []


class ConfigTransformer:
    def __init__(self, region: Optional[str] = None):
        self.region = region or self._get_region()
        self.ssm_client = boto3.client('ssm', region_name=self.region)
        self.secrets_client = boto3.client('secretsmanager', region_name=self.region)
        
    def _get_region(self) -> str:
        """Get AWS region from EC2 metadata or environment"""
        try:
            # Try EC2 metadata
            import requests
            response = requests.get(
                'http://169.254.169.254/latest/meta-data/placement/region',
                timeout=2
            )
            if response.status_code == 200:
                return response.text
        except Exception:
            # Silently use default region if metadata is unavailable
            pass
        
        # Fall back to environment or default
        return os.environ.get('AWS_DEFAULT_REGION', 'us-east-1')
    
    def fetch_secret(self, secret_id: str) -> str:
        """Fetch secret value from AWS Secrets Manager"""
        try:
            response = self.secrets_client.get_secret_value(SecretId=secret_id)
            return response['SecretString']
        except Exception as e:
            # Log error without exposing secret ID details
            print(f"Error fetching secret: Failed to retrieve credentials", file=sys.stderr)
            return "ERROR_FETCHING_SECRET"
    
    def fetch_ssm_parameter(self, parameter_name: str) -> str:
        """Fetch parameter value from SSM Parameter Store"""
        try:
            response = self.ssm_client.get_parameter(
                Name=parameter_name,
                WithDecryption=True
            )
            return response['Parameter']['Value']
        except Exception as e:
            # Log error without exposing parameter name
            print(f"Error fetching SSM parameter: Failed to retrieve credentials", file=sys.stderr)
            return "ERROR_FETCHING_PARAMETER"
    
    def resolve_credentials(self, credentials: Dict[str, Any]) -> Dict[str, Any]:
        """Resolve credentials based on source type"""
        resolved = {}
        
        # Username
        resolved['user'] = credentials.get('username', 'newrelic')
        
        # Password resolution
        password_source = credentials.get('password_source', 'plain')
        
        if password_source == 'aws_secrets_manager':
            password_key = credentials.get('password_key')
            if password_key:
                resolved['password'] = self.fetch_secret(password_key)
            else:
                resolved['password'] = 'MISSING_PASSWORD_KEY'
                
        elif password_source == 'aws_ssm_parameter':
            password_key = credentials.get('password_key')
            if password_key:
                resolved['password'] = self.fetch_ssm_parameter(password_key)
            else:
                resolved['password'] = 'MISSING_PASSWORD_KEY'
                
        elif password_source == 'env_var':
            env_var = credentials.get('password_env')
            if env_var:
                resolved['password'] = os.environ.get(env_var, 'ENV_VAR_NOT_SET')
            else:
                resolved['password'] = 'MISSING_PASSWORD_ENV'
                
        else:  # plain text
            resolved['password'] = credentials.get('password', 'MISSING_PASSWORD')
        
        return resolved
    
    def transform_database(self, db: Dict[str, Any]) -> Dict[str, Any]:
        """Transform enhanced format database to Ansible format"""
        # Skip if disabled
        if not db.get('enabled', True):
            return None
        
        # Resolve credentials
        creds = self.resolve_credentials(db.get('credentials', {}))
        
        # Base configuration
        ansible_db = {
            'host': db.get('connection', {}).get('host') or 
                   db.get('connection', {}).get('endpoint') or 
                   db.get('connection', {}).get('cluster_endpoint'),
            'port': db.get('connection', {}).get('port', 3306 if db['type'] == 'mysql' else 5432),
            'user': creds['user'],
            'password': creds['password'],
            'service_name': db.get('name'),
            'environment': db.get('labels', {}).get('environment', 'production')
        }
        
        # Add database-specific fields
        if db['type'] == 'postgresql':
            ansible_db['database'] = db.get('connection', {}).get('database', 'postgres')
            ansible_db['sslmode'] = db.get('connection', {}).get('ssl_mode', 'require')
        
        # Monitoring settings
        monitoring = db.get('monitoring', {})
        ansible_db['extended_metrics'] = monitoring.get('extended_metrics', True)
        ansible_db['interval'] = monitoring.get('interval', '30s')
        
        # Query monitoring
        ansible_db['enable_query_monitoring'] = monitoring.get('enable_query_monitoring', True)
        ansible_db['query_metrics_interval'] = monitoring.get('query_metrics_interval', '60s')
        ansible_db['max_sql_query_length'] = monitoring.get('max_sql_query_length', 1000)
        ansible_db['gather_query_samples'] = monitoring.get('gather_query_samples', True)
        
        # PostgreSQL specific
        if db['type'] == 'postgresql':
            ansible_db['collect_bloat_metrics'] = monitoring.get('collect_bloat_metrics', True)
            ansible_db['collect_db_lock_metrics'] = monitoring.get('collect_db_lock_metrics', True)
        
        # TLS settings
        if db.get('tls', {}).get('enabled'):
            ansible_db['tls_enabled'] = True
            if db.get('tls', {}).get('ca_bundle_file'):
                ansible_db['tls_ca'] = db['tls']['ca_bundle_file']
        
        # Custom labels
        ansible_db['custom_labels'] = {}
        for key, value in db.get('labels', {}).items():
            if key not in ['environment']:
                ansible_db['custom_labels'][key] = value
        
        return ansible_db
    
    def transform_config(self, input_config: Dict[str, Any]) -> Dict[str, Any]:
        """Transform enhanced JSON config to Ansible YAML format"""
        output_config = {
            'newrelic_license_key': os.environ.get('NEWRELIC_LICENSE_KEY', 'YOUR_LICENSE_KEY'),
            'newrelic_account_id': os.environ.get('NEWRELIC_ACCOUNT_ID', 'YOUR_ACCOUNT_ID')
        }
        
        # Transform MySQL databases
        mysql_dbs = []
        for db in input_config.get('mysql_databases', []):
            transformed = self.transform_database(db)
            if transformed:
                mysql_dbs.append(transformed)
        
        if mysql_dbs:
            output_config['mysql_databases'] = mysql_dbs
        
        # Transform PostgreSQL databases
        postgres_dbs = []
        for db in input_config.get('postgresql_databases', []):
            transformed = self.transform_database(db)
            if transformed:
                postgres_dbs.append(transformed)
        
        if postgres_dbs:
            output_config['postgresql_databases'] = postgres_dbs
        
        return output_config
    
    def process_file(self, input_file: str, output_file: str):
        """Process configuration file"""
        print(f"Reading configuration from {input_file}...")
        
        with open(input_file, 'r') as f:
            if input_file.endswith('.json'):
                input_config = json.load(f)
            else:
                input_config = yaml.safe_load(f)
        
        # Validate input configuration
        print("Validating configuration...")
        valid, errors, warnings = validate_yaml_config(input_config)
        
        if not valid:
            print("\nConfiguration validation failed:")
            for error in errors:
                print(f"  ERROR: {error}")
            if warnings:
                print("\nWarnings:")
                for warning in warnings:
                    print(f"  WARNING: {warning}")
            raise ValueError("Invalid configuration")
        
        if warnings:
            print("\nConfiguration warnings:")
            for warning in warnings:
                print(f"  WARNING: {warning}")
        
        print("Transforming configuration...")
        output_config = self.transform_config(input_config)
        
        print(f"Writing transformed configuration to {output_file}...")
        # Create file with secure permissions
        import os
        import stat
        
        # Write to temporary file first
        temp_file = f"{output_file}.tmp"
        with open(temp_file, 'w') as f:
            yaml.dump(output_config, f, default_flow_style=False, sort_keys=False)
        
        # Set secure permissions (owner read/write only)
        os.chmod(temp_file, stat.S_IRUSR | stat.S_IWUSR)
        
        # Move to final location
        os.rename(temp_file, output_file)
        
        # Summary
        mysql_count = len(output_config.get('mysql_databases', []))
        postgres_count = len(output_config.get('postgresql_databases', []))
        print(f"\nTransformation complete:")
        print(f"  MySQL databases: {mysql_count}")
        print(f"  PostgreSQL databases: {postgres_count}")
        
        # Check for errors without exposing passwords
        error_count = 0
        for db_list in [output_config.get('mysql_databases', []), 
                       output_config.get('postgresql_databases', [])]:
            for db in db_list:
                if 'ERROR' in db.get('password', ''):
                    error_count += 1
                    print(f"\nWARNING: Failed to resolve credentials for database: {db.get('service_name', 'unknown')}")
        
        if error_count > 0:
            print(f"\nTotal credential resolution errors: {error_count}")
            print("Please check your AWS credentials and ensure the secrets/parameters exist.")


def main():
    parser = argparse.ArgumentParser(
        description='Transform database configuration from enhanced format to Ansible format'
    )
    parser.add_argument(
        'input_file',
        help='Input configuration file (JSON or YAML)'
    )
    parser.add_argument(
        'output_file',
        help='Output configuration file (YAML)'
    )
    parser.add_argument(
        '--region',
        help='AWS region (auto-detected if not specified)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be transformed without writing output'
    )
    
    args = parser.parse_args()
    
    # Validate input file exists
    if not os.path.exists(args.input_file):
        print(f"Error: Input file '{args.input_file}' not found", file=sys.stderr)
        sys.exit(1)
    
    # Create transformer
    transformer = ConfigTransformer(region=args.region)
    
    try:
        if args.dry_run:
            with open(args.input_file, 'r') as f:
                if args.input_file.endswith('.json'):
                    input_config = json.load(f)
                else:
                    input_config = yaml.safe_load(f)
            
            output_config = transformer.transform_config(input_config)
            print("Transformed configuration (dry run):")
            print(yaml.dump(output_config, default_flow_style=False))
        else:
            transformer.process_file(args.input_file, args.output_file)
            
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()