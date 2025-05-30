#!/usr/bin/env python3
"""
Credential validation script
Validates database credentials before running monitoring setup
"""

import yaml
import json
import sys
import os
import pymysql
import psycopg2
from typing import Dict, Any, List, Tuple
import argparse
import boto3
from datetime import datetime


class CredentialValidator:
    def __init__(self, config_file: str, fix_errors: bool = False):
        self.config_file = config_file
        self.fix_errors = fix_errors
        self.errors = []
        self.warnings = []
        self.region = self._get_region()
        
    def _get_region(self) -> str:
        """Get AWS region"""
        try:
            import requests
            response = requests.get(
                'http://169.254.169.254/latest/meta-data/placement/region',
                timeout=2
            )
            if response.status_code == 200:
                return response.text
        except:
            pass
        return os.environ.get('AWS_DEFAULT_REGION', 'us-east-1')
    
    def load_config(self) -> Dict[str, Any]:
        """Load configuration file"""
        with open(self.config_file, 'r') as f:
            if self.config_file.endswith('.json'):
                return json.load(f)
            else:
                return yaml.safe_load(f)
    
    def test_mysql_connection(self, db: Dict[str, Any]) -> Tuple[bool, str]:
        """Test MySQL database connection"""
        try:
            # SSL configuration
            ssl_config = None
            if db.get('ssl', False) or db.get('tls', False):
                ssl_config = {'ssl': {'ssl_disabled': False}}
            
            connection = pymysql.connect(
                host=db['host'],
                port=db.get('port', 3306),
                user=db['user'],
                password=db['password'],
                database=db.get('database', 'information_schema'),
                connect_timeout=10,
                ssl=ssl_config
            )
            
            with connection.cursor() as cursor:
                # Test basic connectivity
                cursor.execute("SELECT VERSION()")
                version = cursor.fetchone()[0]
                
                # Test required permissions
                cursor.execute("SHOW GRANTS FOR CURRENT_USER()")
                grants = [row[0] for row in cursor.fetchall()]
                
                # Check for required permissions
                required_permissions = ['SELECT', 'PROCESS', 'REPLICATION CLIENT']
                missing_permissions = []
                
                grants_str = ' '.join(grants).upper()
                for perm in required_permissions:
                    if perm not in grants_str:
                        missing_permissions.append(perm)
                
                if missing_permissions:
                    return False, f"Missing permissions: {', '.join(missing_permissions)}"
                
                # Check performance_schema access
                cursor.execute("SELECT COUNT(*) FROM performance_schema.setup_consumers")
                
            connection.close()
            return True, f"Connected successfully (MySQL {version})"
            
        except pymysql.err.OperationalError as e:
            # Log connection error without exposing details
            return False, "Connection failed: Unable to connect to MySQL database"
        except pymysql.err.ProgrammingError as e:
            return False, "Permission error: Insufficient database privileges"
        except Exception as e:
            # Log error without exposing sensitive information
            return False, "Connection failed: Database connection error"
    
    def test_postgresql_connection(self, db: Dict[str, Any]) -> Tuple[bool, str]:
        """Test PostgreSQL database connection"""
        try:
            connection = psycopg2.connect(
                host=db['host'],
                port=db.get('port', 5432),
                user=db['user'],
                password=db['password'],
                database=db.get('database', 'postgres'),
                connect_timeout=10,
                sslmode=db.get('sslmode', 'require')  # Default to require SSL
            )
            
            with connection.cursor() as cursor:
                # Test basic connectivity
                cursor.execute("SELECT version()")
                version = cursor.fetchone()[0]
                
                # Check for pg_monitor role
                cursor.execute("""
                    SELECT pg_has_role(%s, 'pg_monitor', 'USAGE') OR
                           pg_has_role(%s, 'pg_read_all_stats', 'USAGE')
                """, (db['user'], db['user']))
                has_monitor_role = cursor.fetchone()[0]
                
                if not has_monitor_role:
                    # Check individual permissions
                    cursor.execute("""
                        SELECT has_table_privilege(%s, 'pg_stat_database', 'SELECT')
                    """, (db['user'],))
                    has_basic_perms = cursor.fetchone()[0]
                    
                    if not has_basic_perms:
                        return False, "Missing pg_monitor role or equivalent permissions"
                
                # Check pg_stat_statements extension
                cursor.execute("""
                    SELECT COUNT(*) FROM pg_extension WHERE extname = 'pg_stat_statements'
                """)
                has_pg_stat_statements = cursor.fetchone()[0] > 0
                
                if not has_pg_stat_statements:
                    self.warnings.append(
                        f"{db.get('service_name', db['host'])}: "
                        "pg_stat_statements extension not installed (query monitoring limited)"
                    )
            
            connection.close()
            return True, f"Connected successfully (PostgreSQL)"
            
        except psycopg2.OperationalError as e:
            # Log connection error without exposing details
            return False, "Connection failed: Unable to connect to PostgreSQL database"
        except psycopg2.ProgrammingError as e:
            return False, "Permission error: Insufficient database privileges"
        except Exception as e:
            # Log error without exposing sensitive information
            return False, "Connection failed: Database connection error"
    
    def validate_credentials(self) -> bool:
        """Validate all database credentials"""
        print("Loading configuration...")
        try:
            config = self.load_config()
        except Exception as e:
            print(f"ERROR: Failed to load configuration: {e}")
            return False
        
        all_valid = True
        
        # Validate New Relic credentials
        nr_key = config.get('newrelic_license_key', '')
        if not nr_key or nr_key == 'YOUR_LICENSE_KEY':
            self.errors.append("New Relic license key not configured")
            all_valid = False
        else:
            print("✓ New Relic license key configured")
        
        # Validate MySQL databases
        mysql_dbs = config.get('mysql_databases', [])
        if mysql_dbs:
            print(f"\nValidating {len(mysql_dbs)} MySQL database(s)...")
            for db in mysql_dbs:
                name = db.get('service_name', db['host'])
                print(f"  Checking {name}...", end=' ')
                
                # Check for credential errors
                if 'ERROR' in db.get('password', ''):
                    print("✗ Failed to resolve credentials")
                    self.errors.append(f"{name}: Credential resolution failed")
                    all_valid = False
                    continue
                
                # Test connection
                success, message = self.test_mysql_connection(db)
                if success:
                    print(f"✓ {message}")
                else:
                    print(f"✗ {message}")
                    self.errors.append(f"{name}: {message}")
                    all_valid = False
        
        # Validate PostgreSQL databases
        postgres_dbs = config.get('postgresql_databases', [])
        if postgres_dbs:
            print(f"\nValidating {len(postgres_dbs)} PostgreSQL database(s)...")
            for db in postgres_dbs:
                name = db.get('service_name', db['host'])
                print(f"  Checking {name}...", end=' ')
                
                # Check for credential errors
                if 'ERROR' in db.get('password', ''):
                    print("✗ Failed to resolve credentials")
                    self.errors.append(f"{name}: Credential resolution failed")
                    all_valid = False
                    continue
                
                # Test connection
                success, message = self.test_postgresql_connection(db)
                if success:
                    print(f"✓ {message}")
                else:
                    print(f"✗ {message}")
                    self.errors.append(f"{name}: {message}")
                    all_valid = False
        
        return all_valid
    
    def generate_fix_script(self) -> str:
        """Generate script to fix credential issues"""
        fixes = []
        fixes.append("#!/bin/bash")
        fixes.append("# Script to fix credential issues")
        fixes.append(f"# Generated: {datetime.now().isoformat()}")
        fixes.append("")
        
        for error in self.errors:
            if "Credential resolution failed" in error:
                db_name = error.split(':')[0]
                fixes.append(f"# Fix credential resolution for: {db_name}")
                fixes.append("# Check AWS credentials and ensure secrets/parameters exist")
                fixes.append("# Example commands:")
                fixes.append("# aws secretsmanager create-secret --name db-password --secret-string 'YOUR_PASSWORD'")
                fixes.append("# aws ssm put-parameter --name /db/password --value 'YOUR_PASSWORD' --type SecureString")
                fixes.append("")
            elif "Missing permissions" in error:
                db_name = error.split(':')[0]
                permissions = error.split('Missing permissions: ')[1]
                fixes.append(f"# Fix permissions for {db_name}")
                fixes.append(f"# MySQL: GRANT {permissions} ON *.* TO 'newrelic'@'%';")
                fixes.append("")
            elif "Missing pg_monitor role" in error:
                db_name = error.split(':')[0]
                fixes.append(f"# Fix permissions for {db_name}")
                fixes.append(f"# PostgreSQL: GRANT pg_monitor TO newrelic;")
                fixes.append("")
        
        return '\n'.join(fixes)
    
    def run(self) -> int:
        """Run validation and return exit code"""
        print("=" * 60)
        print("Database Credential Validation")
        print("=" * 60)
        
        valid = self.validate_credentials()
        
        # Print summary
        print("\n" + "=" * 60)
        print("VALIDATION SUMMARY")
        print("=" * 60)
        
        if self.warnings:
            print(f"\nWarnings ({len(self.warnings)}):")
            for warning in self.warnings:
                print(f"  ⚠ {warning}")
        
        if self.errors:
            print(f"\nErrors ({len(self.errors)}):")
            for error in self.errors:
                print(f"  ✗ {error}")
            
            if self.fix_errors:
                print("\nGenerating fix script...")
                fix_script = self.generate_fix_script()
                fix_file = "fix-credentials.sh"
                with open(fix_file, 'w') as f:
                    f.write(fix_script)
                os.chmod(fix_file, 0o600)  # Secure permissions - owner read/write only
                print(f"Fix script written to: {fix_file}")
        else:
            print("\n✓ All credentials validated successfully!")
        
        return 0 if valid else 1


def main():
    parser = argparse.ArgumentParser(
        description='Validate database credentials for New Relic monitoring'
    )
    parser.add_argument(
        'config_file',
        help='Configuration file to validate (YAML or JSON)'
    )
    parser.add_argument(
        '--fix',
        action='store_true',
        help='Generate fix script for credential issues'
    )
    parser.add_argument(
        '--skip-connection-test',
        action='store_true',
        help='Skip actual connection tests (only check configuration)'
    )
    
    args = parser.parse_args()
    
    if not os.path.exists(args.config_file):
        print(f"ERROR: Configuration file not found: {args.config_file}")
        sys.exit(1)
    
    # Check required packages
    try:
        import pymysql
        import psycopg2
    except ImportError as e:
        print("ERROR: Required packages not installed")
        print("Run: pip3 install pymysql psycopg2-binary boto3 pyyaml")
        sys.exit(1)
    
    validator = CredentialValidator(args.config_file, args.fix)
    sys.exit(validator.run())


if __name__ == '__main__':
    main()