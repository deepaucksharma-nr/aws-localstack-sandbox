"""Integration tests for services"""

import pytest
import requests
import boto3
import time
import mysql.connector
import psycopg2
import os


class TestLocalStackIntegration:
    """Test LocalStack AWS services"""
    
    @pytest.fixture
    def localstack_client(self):
        """Create LocalStack client"""
        return boto3.client(
            'ec2',
            endpoint_url=os.environ.get('LOCALSTACK_ENDPOINT', 'http://localhost:4566'),
            region_name='us-east-1',
            aws_access_key_id='test',
            aws_secret_access_key='test'
        )
    
    def test_localstack_health(self):
        """Test LocalStack is healthy"""
        response = requests.get('http://localstack:4566/_localstack/health')
        assert response.status_code == 200
        data = response.json()
        assert 'services' in data
    
    def test_vpc_creation(self, localstack_client):
        """Test VPC can be created in LocalStack"""
        response = localstack_client.create_vpc(CidrBlock='10.0.0.0/16')
        assert 'Vpc' in response
        assert 'VpcId' in response['Vpc']
        
        # Clean up
        localstack_client.delete_vpc(VpcId=response['Vpc']['VpcId'])
    
    def test_security_group_creation(self, localstack_client):
        """Test security group creation"""
        # First create a VPC
        vpc_response = localstack_client.create_vpc(CidrBlock='10.0.0.0/16')
        vpc_id = vpc_response['Vpc']['VpcId']
        
        # Create security group
        sg_response = localstack_client.create_security_group(
            GroupName='test-sg',
            Description='Test security group',
            VpcId=vpc_id
        )
        assert 'GroupId' in sg_response
        
        # Clean up
        localstack_client.delete_security_group(GroupId=sg_response['GroupId'])
        localstack_client.delete_vpc(VpcId=vpc_id)


class TestMySQLIntegration:
    """Test MySQL database connectivity"""
    
    @pytest.fixture
    def mysql_connection(self):
        """Create MySQL connection"""
        conn = mysql.connector.connect(
            host=os.environ.get('MYSQL_HOST', 'mysql-test'),
            user='newrelic',
            password='newrelic123',
            database='testdb'
        )
        yield conn
        conn.close()
    
    def test_mysql_connectivity(self, mysql_connection):
        """Test MySQL is accessible"""
        cursor = mysql_connection.cursor()
        cursor.execute("SELECT 1")
        result = cursor.fetchone()
        assert result[0] == 1
        cursor.close()
    
    def test_mysql_permissions(self, mysql_connection):
        """Test New Relic user has correct permissions"""
        cursor = mysql_connection.cursor()
        cursor.execute("SHOW GRANTS FOR CURRENT_USER()")
        grants = cursor.fetchall()
        cursor.close()
        
        # Check for required permissions
        grants_str = str(grants)
        assert 'SELECT' in grants_str
        assert 'PROCESS' in grants_str
        assert 'REPLICATION CLIENT' in grants_str
    
    def test_mysql_test_data(self, mysql_connection):
        """Test that test data exists"""
        cursor = mysql_connection.cursor()
        cursor.execute("SELECT COUNT(*) FROM app_db.users")
        count = cursor.fetchone()[0]
        assert count > 0, "No test users found"
        cursor.close()


class TestPostgreSQLIntegration:
    """Test PostgreSQL database connectivity"""
    
    @pytest.fixture
    def postgres_connection(self):
        """Create PostgreSQL connection"""
        conn = psycopg2.connect(
            host=os.environ.get('POSTGRES_HOST', 'postgres-test'),
            port=5432,
            user='newrelic',
            password='newrelic123',
            database='testdb'
        )
        yield conn
        conn.close()
    
    def test_postgres_connectivity(self, postgres_connection):
        """Test PostgreSQL is accessible"""
        cursor = postgres_connection.cursor()
        cursor.execute("SELECT 1")
        result = cursor.fetchone()
        assert result[0] == 1
        cursor.close()
    
    def test_postgres_permissions(self, postgres_connection):
        """Test New Relic user has correct permissions"""
        cursor = postgres_connection.cursor()
        cursor.execute("""
            SELECT has_table_privilege('newrelic', 'pg_stat_database', 'SELECT')
        """)
        result = cursor.fetchone()
        assert result[0] is True, "Missing SELECT permission on pg_stat_database"
        cursor.close()
    
    def test_postgres_test_data(self, postgres_connection):
        """Test that test data exists"""
        cursor = postgres_connection.cursor()
        cursor.execute("SELECT COUNT(*) FROM users")
        count = cursor.fetchone()[0]
        assert count > 0, "No test users found"
        cursor.close()


class TestMockNewRelicIntegration:
    """Test mock New Relic API"""
    
    def test_mock_api_health(self):
        """Test mock API is healthy"""
        response = requests.get('http://mock-newrelic:8080/health')
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'ok'
    
    def test_mock_infra_health(self):
        """Test mock infrastructure endpoint is healthy"""
        response = requests.get('http://mock-newrelic:8081/health')
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'ok'
    
    def test_agent_registration(self):
        """Test agent can register with mock server"""
        response = requests.post(
            'http://mock-newrelic:8081/identity/v1/connect',
            json={
                'license_key': 'test_license_key_123',
                'hostname': 'test-host'
            }
        )
        assert response.status_code == 200
        data = response.json()
        assert 'agent_id' in data
        assert data['status'] == 'connected'
    
    def test_metrics_ingestion(self):
        """Test metrics can be sent to mock server"""
        # First register an agent
        reg_response = requests.post(
            'http://mock-newrelic:8081/identity/v1/connect',
            json={
                'license_key': 'test_license_key_123',
                'hostname': 'test-host'
            }
        )
        agent_id = reg_response.json()['agent_id']
        
        # Send metrics
        metrics_response = requests.post(
            'http://mock-newrelic:8081/agent/v1/metrics',
            headers={'X-Agent-Id': agent_id},
            json={
                'metrics': [
                    {
                        'name': 'test.metric',
                        'value': 42,
                        'timestamp': int(time.time())
                    }
                ]
            }
        )
        assert metrics_response.status_code == 200
        assert metrics_response.json()['status'] == 'accepted'


class TestEndToEndFlow:
    """Test complete flow"""
    
    def test_database_monitoring_configuration(self):
        """Test that database monitoring can be configured"""
        # This would be expanded to test the full flow
        # For now, just verify services are accessible
        
        # Check MySQL
        mysql_conn = mysql.connector.connect(
            host='mysql-test',
            user='newrelic',
            password='newrelic123',
            database='testdb'
        )
        mysql_conn.close()
        
        # Check PostgreSQL
        pg_conn = psycopg2.connect(
            host='postgres-test',
            port=5432,
            user='newrelic',
            password='newrelic123',
            database='testdb'
        )
        pg_conn.close()
        
        # Check mock New Relic
        response = requests.get('http://mock-newrelic:8080/health')
        assert response.status_code == 200