#!/usr/bin/env python3
"""
AWS Database Discovery Script
Discovers RDS and Aurora instances/clusters and generates New Relic monitoring configuration
"""

import boto3
import json
import yaml
import argparse
import sys
from typing import Dict, List, Any, Optional
from datetime import datetime


class DatabaseDiscovery:
    def __init__(self, regions: List[str], tag_filters: Optional[Dict[str, str]] = None):
        self.regions = regions
        self.tag_filters = tag_filters or {'monitor': 'newrelic'}
        self.databases = []
        
    def discover_rds_instances(self, region: str) -> List[Dict[str, Any]]:
        """Discover RDS instances in a specific region"""
        rds = boto3.client('rds', region_name=region)
        instances = []
        
        try:
            paginator = rds.get_paginator('describe_db_instances')
            for page in paginator.paginate():
                for instance in page['DBInstances']:
                    # Check if instance matches tag filters
                    if self._matches_tags(rds, instance['DBInstanceArn']):
                        instances.append(self._parse_rds_instance(instance, region))
        except Exception as e:
            print(f"Error discovering RDS instances in {region}: {e}", file=sys.stderr)
            
        return instances
    
    def discover_aurora_clusters(self, region: str) -> List[Dict[str, Any]]:
        """Discover Aurora clusters in a specific region"""
        rds = boto3.client('rds', region_name=region)
        clusters = []
        
        try:
            paginator = rds.get_paginator('describe_db_clusters')
            for page in paginator.paginate():
                for cluster in page['DBClusters']:
                    # Check if cluster matches tag filters
                    if self._matches_tags(rds, cluster['DBClusterArn']):
                        clusters.append(self._parse_aurora_cluster(cluster, region))
        except Exception as e:
            print(f"Error discovering Aurora clusters in {region}: {e}", file=sys.stderr)
            
        return clusters
    
    def _matches_tags(self, rds_client, resource_arn: str) -> bool:
        """Check if resource tags match our filters"""
        if not self.tag_filters:
            return True
            
        try:
            response = rds_client.list_tags_for_resource(ResourceName=resource_arn)
            resource_tags = {tag['Key']: tag['Value'] for tag in response.get('TagList', [])}
            
            for key, value in self.tag_filters.items():
                if resource_tags.get(key) != value:
                    return False
            return True
        except Exception:
            return False
    
    def _parse_rds_instance(self, instance: Dict[str, Any], region: str) -> Dict[str, Any]:
        """Parse RDS instance details into our configuration format"""
        engine = instance['Engine']
        
        # Determine database type
        if 'mysql' in engine:
            db_type = 'mysql'
        elif 'postgres' in engine:
            db_type = 'postgresql'
        else:
            db_type = engine
            
        # Get tags for labels
        tags = self._get_resource_tags(instance.get('TagList', []))
        
        config = {
            'name': instance['DBInstanceIdentifier'],
            'enabled': instance['DBInstanceStatus'] == 'available',
            'type': db_type,
            'provider': 'rds',
            'connection': {
                'endpoint': instance['Endpoint']['Address'],
                'port': instance['Endpoint']['Port']
            },
            'credentials': {
                'username': instance.get('MasterUsername', 'admin'),
                'password_source': 'aws_secrets_manager',
                'password_key': f"/rds/{region}/{instance['DBInstanceIdentifier']}/newrelic"
            },
            'monitoring': {
                'collect_inventory': True,
                'extended_metrics': True,
                'collect_rds_metrics': True,
                'enable_query_monitoring': True
            },
            'tls': {
                'enabled': True
            },
            'labels': {
                'environment': tags.get('Environment', tags.get('env', 'unknown')),
                'region': region,
                'engine': engine,
                'engine_version': instance.get('EngineVersion', 'unknown'),
                'instance_class': instance.get('DBInstanceClass', 'unknown'),
                'multi_az': str(instance.get('MultiAZ', False)).lower()
            }
        }
        
        # Add custom labels from tags
        for key, value in tags.items():
            if key not in ['Environment', 'env', 'monitor']:
                config['labels'][key] = value
                
        return config
    
    def _parse_aurora_cluster(self, cluster: Dict[str, Any], region: str) -> Dict[str, Any]:
        """Parse Aurora cluster details into our configuration format"""
        engine = cluster['Engine']
        
        # Determine database type
        if 'mysql' in engine:
            db_type = 'mysql'
        elif 'postgres' in engine:
            db_type = 'postgresql'
        else:
            db_type = engine
            
        # Get tags for labels
        tags = self._get_resource_tags(cluster.get('TagList', []))
        
        config = {
            'name': cluster['DBClusterIdentifier'],
            'enabled': cluster['Status'] == 'available',
            'type': db_type,
            'provider': 'aurora',
            'connection': {
                'cluster_endpoint': cluster.get('Endpoint'),
                'reader_endpoint': cluster.get('ReaderEndpoint'),
                'port': cluster.get('Port', 3306 if 'mysql' in engine else 5432)
            },
            'credentials': {
                'username': cluster.get('MasterUsername', 'admin'),
                'password_source': 'aws_secrets_manager',
                'password_key': f"/aurora/{region}/{cluster['DBClusterIdentifier']}/newrelic",
                'region': region
            },
            'monitoring': {
                'collect_inventory': True,
                'extended_metrics': True,
                'collect_aurora_metrics': True,
                'monitor_readers': True,
                'enable_query_monitoring': True
            },
            'tls': {
                'enabled': True,
                'verify_server_certificate': True
            },
            'labels': {
                'environment': tags.get('Environment', tags.get('env', 'unknown')),
                'region': region,
                'engine': engine,
                'engine_version': cluster.get('EngineVersion', 'unknown'),
                'cluster_type': 'aurora',
                'ha_enabled': 'true'
            }
        }
        
        # Add custom labels from tags
        for key, value in tags.items():
            if key not in ['Environment', 'env', 'monitor']:
                config['labels'][key] = value
                
        return config
    
    def _get_resource_tags(self, tag_list: List[Dict[str, str]]) -> Dict[str, str]:
        """Convert tag list to dictionary"""
        return {tag['Key']: tag['Value'] for tag in tag_list}
    
    def discover_all(self) -> Dict[str, List[Dict[str, Any]]]:
        """Discover all databases across all regions"""
        mysql_databases = []
        postgresql_databases = []
        
        for region in self.regions:
            print(f"Discovering databases in {region}...")
            
            # Discover RDS instances
            rds_instances = self.discover_rds_instances(region)
            for db in rds_instances:
                if db['type'] == 'mysql':
                    mysql_databases.append(db)
                elif db['type'] == 'postgresql':
                    postgresql_databases.append(db)
                    
            # Discover Aurora clusters
            aurora_clusters = self.discover_aurora_clusters(region)
            for db in aurora_clusters:
                if db['type'] == 'mysql':
                    mysql_databases.append(db)
                elif db['type'] == 'postgresql':
                    postgresql_databases.append(db)
        
        return {
            'mysql_databases': mysql_databases,
            'postgresql_databases': postgresql_databases
        }
    
    def generate_config(self, output_format: str = 'yaml') -> str:
        """Generate configuration in specified format"""
        config = self.discover_all()
        
        # Add metadata
        config['_metadata'] = {
            'generated_at': datetime.utcnow().isoformat(),
            'regions_scanned': self.regions,
            'tag_filters': self.tag_filters
        }
        
        if output_format == 'yaml':
            return yaml.dump(config, default_flow_style=False, sort_keys=False)
        elif output_format == 'json':
            return json.dumps(config, indent=2)
        else:
            raise ValueError(f"Unsupported output format: {output_format}")


def main():
    parser = argparse.ArgumentParser(
        description='Discover AWS RDS and Aurora databases for New Relic monitoring'
    )
    parser.add_argument(
        '--regions',
        nargs='+',
        default=['us-east-1'],
        help='AWS regions to scan (default: us-east-1)'
    )
    parser.add_argument(
        '--tag-filter',
        action='append',
        help='Tag filter in key=value format (can be specified multiple times)'
    )
    parser.add_argument(
        '--output',
        choices=['yaml', 'json'],
        default='yaml',
        help='Output format (default: yaml)'
    )
    parser.add_argument(
        '--output-file',
        help='Output file path (default: stdout)'
    )
    parser.add_argument(
        '--include-disabled',
        action='store_true',
        help='Include databases that are not in "available" state'
    )
    
    args = parser.parse_args()
    
    # Parse tag filters
    tag_filters = {}
    if args.tag_filter:
        for tag in args.tag_filter:
            if '=' in tag:
                key, value = tag.split('=', 1)
                tag_filters[key] = value
            else:
                print(f"Invalid tag filter format: {tag}", file=sys.stderr)
                sys.exit(1)
    
    # Run discovery
    discovery = DatabaseDiscovery(regions=args.regions, tag_filters=tag_filters)
    
    try:
        config = discovery.generate_config(output_format=args.output)
        
        if args.output_file:
            with open(args.output_file, 'w') as f:
                f.write(config)
            print(f"Configuration written to {args.output_file}")
        else:
            print(config)
            
    except Exception as e:
        print(f"Error generating configuration: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()