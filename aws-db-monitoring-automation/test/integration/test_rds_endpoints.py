#!/usr/bin/env python3
"""
Integration tests for RDS endpoint connectivity
Tests both container mode and simulated RDS endpoints
"""

import os
import sys
import time
import pytest
import pymysql
import psycopg2
from typing import Dict, Any, Optional


class TestRDSEndpoints:
    """Test database connectivity for different provider modes"""
    
    @pytest.fixture
    def mysql_configs(self) -> Dict[str, Dict[str, Any]]:
        """MySQL connection configurations for different providers"""
        return {
            'container': {
                'host': os.environ.get('MYSQL_HOST', 'mysql'),
                'port': int(os.environ.get('MYSQL_PORT', 3306)),
                'user': 'newrelic',
                'password': 'nr_password123',
                'database': 'testdb'
            },
            'rds_simulated': {
                'host': os.environ.get('RDS_MYSQL_ENDPOINT', 'rds-simulator').split(':')[0],
                'port': int(os.environ.get('RDS_MYSQL_ENDPOINT', 'rds-simulator:13306').split(':')[1]),
                'user': 'newrelic',
                'password': 'nr_password123',
                'database': 'testdb'
            }
        }
    
    @pytest.fixture
    def postgres_configs(self) -> Dict[str, Dict[str, Any]]:
        """PostgreSQL connection configurations for different providers"""
        return {
            'container': {
                'host': os.environ.get('POSTGRES_HOST', 'postgres'),
                'port': int(os.environ.get('POSTGRES_PORT', 5432)),
                'user': 'postgres',
                'password': 'rootpassword',
                'database': 'testdb'
            },
            'rds_simulated': {
                'host': os.environ.get('RDS_POSTGRES_ENDPOINT', 'rds-simulator').split(':')[0],
                'port': int(os.environ.get('RDS_POSTGRES_ENDPOINT', 'rds-simulator:15432').split(':')[1]),
                'user': 'postgres',
                'password': 'rootpassword',
                'database': 'testdb'
            }
        }
    
    def test_mysql_container_connection(self, mysql_configs):
        """Test MySQL container connectivity"""
        config = mysql_configs['container']
        connection = None
        
        try:
            connection = pymysql.connect(**config)
            with connection.cursor() as cursor:
                # Test basic query
                cursor.execute("SELECT VERSION()")
                version = cursor.fetchone()[0]
                assert '8.0' in version
                
                # Test performance schema
                cursor.execute("""
                    SELECT COUNT(*) 
                    FROM performance_schema.events_statements_current 
                    WHERE EVENT_NAME IS NOT NULL
                """)
                result = cursor.fetchone()[0]
                assert result >= 0
                
            print(f"✓ MySQL container connection successful (version: {version})")
            
        finally:
            if connection:
                connection.close()
    
    def test_postgres_container_connection(self, postgres_configs):
        """Test PostgreSQL container connectivity"""
        config = postgres_configs['container']
        connection = None
        
        try:
            connection = psycopg2.connect(**config)
            with connection.cursor() as cursor:
                # Test basic query
                cursor.execute("SELECT version()")
                version = cursor.fetchone()[0]
                assert 'PostgreSQL 15' in version
                
                # Test pg_stat_statements
                cursor.execute("""
                    SELECT COUNT(*) 
                    FROM pg_extension 
                    WHERE extname = 'pg_stat_statements'
                """)
                result = cursor.fetchone()[0]
                assert result == 1
                
            print(f"✓ PostgreSQL container connection successful")
            
        finally:
            if connection:
                connection.close()
    
    @pytest.mark.skipif(
        'RDS_TEST' not in os.environ,
        reason="RDS simulation tests only run when RDS_TEST env var is set"
    )
    def test_mysql_rds_simulated_connection(self, mysql_configs):
        """Test simulated RDS MySQL endpoint connectivity"""
        config = mysql_configs['rds_simulated']
        connection = None
        
        # Wait for RDS simulator to be ready
        time.sleep(2)
        
        try:
            connection = pymysql.connect(**config)
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                result = cursor.fetchone()[0]
                assert result == 1
                
            print("✓ Simulated RDS MySQL endpoint connection successful")
            
        finally:
            if connection:
                connection.close()
    
    @pytest.mark.skipif(
        'RDS_TEST' not in os.environ,
        reason="RDS simulation tests only run when RDS_TEST env var is set"
    )
    def test_postgres_rds_simulated_connection(self, postgres_configs):
        """Test simulated RDS PostgreSQL endpoint connectivity"""
        config = postgres_configs['rds_simulated']
        connection = None
        
        # Wait for RDS simulator to be ready
        time.sleep(2)
        
        try:
            connection = psycopg2.connect(**config)
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                result = cursor.fetchone()[0]
                assert result == 1
                
            print("✓ Simulated RDS PostgreSQL endpoint connection successful")
            
        finally:
            if connection:
                connection.close()
    
    def test_enhanced_configuration_format(self):
        """Test that enhanced configuration format is properly structured"""
        import yaml
        
        # Sample enhanced configuration
        enhanced_config = {
            'mysql_databases': [{
                'name': 'test-mysql-rds',
                'type': 'mysql',
                'provider': 'rds',
                'connection': {
                    'endpoint': 'test.abc123.us-east-1.rds.amazonaws.com',
                    'port': 3306
                },
                'credentials': {
                    'username': 'newrelic',
                    'password_source': 'aws_secrets_manager',
                    'password_key': '/prod/mysql/password'
                },
                'monitoring': {
                    'extended_metrics': True,
                    'collect_rds_metrics': True,
                    'enable_query_monitoring': True
                }
            }],
            'postgresql_databases': [{
                'name': 'test-postgres-aurora',
                'type': 'postgresql',
                'provider': 'aurora',
                'connection': {
                    'cluster_endpoint': 'test-cluster.cluster-abc123.us-east-1.rds.amazonaws.com',
                    'reader_endpoint': 'test-cluster.cluster-ro-abc123.us-east-1.rds.amazonaws.com',
                    'port': 5432
                },
                'credentials': {
                    'username': 'newrelic',
                    'password_source': 'aws_ssm_parameter',
                    'password_key': '/prod/aurora/password'
                },
                'monitoring': {
                    'extended_metrics': True,
                    'collect_aurora_metrics': True,
                    'monitor_readers': True,
                    'enable_query_monitoring': True
                }
            }]
        }
        
        # Validate structure
        assert 'mysql_databases' in enhanced_config
        assert 'postgresql_databases' in enhanced_config
        
        # Validate MySQL RDS configuration
        mysql_db = enhanced_config['mysql_databases'][0]
        assert mysql_db['provider'] == 'rds'
        assert 'endpoint' in mysql_db['connection']
        assert mysql_db['credentials']['password_source'] == 'aws_secrets_manager'
        assert mysql_db['monitoring']['collect_rds_metrics'] is True
        
        # Validate PostgreSQL Aurora configuration
        postgres_db = enhanced_config['postgresql_databases'][0]
        assert postgres_db['provider'] == 'aurora'
        assert 'cluster_endpoint' in postgres_db['connection']
        assert 'reader_endpoint' in postgres_db['connection']
        assert postgres_db['monitoring']['collect_aurora_metrics'] is True
        assert postgres_db['monitoring']['monitor_readers'] is True
        
        print("✓ Enhanced configuration format validation successful")


if __name__ == '__main__':
    # Run tests
    pytest.main([__file__, '-v'])