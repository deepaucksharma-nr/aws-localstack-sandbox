# Modular Database Monitoring Architecture

## Overview

This enhanced architecture supports multiple database providers (containers, EC2, RDS, Aurora) with a unified monitoring approach using New Relic.

## Architecture Components

```
┌─────────────────────────────────────────────────────────────┐
│                     New Relic Platform                      │
│                  (Metrics & Query Analysis)                 │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────┴────────────────────────────────────┐
│                  Monitoring EC2 Instance                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │          New Relic Infrastructure Agent              │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │  MySQL Integration  │  PostgreSQL Integration       │   │
│  └─────────────┬───────────────────┬───────────────────┘   │
└────────────────┼───────────────────┼────────────────────────┘
                 │                   │
   ┌─────────────┴─────────┐ ┌──────┴──────────────────┐
   │   Database Providers  │ │   Credential Sources    │
   ├───────────────────────┤ ├──────────────────────────┤
   │ • Container (Docker)  │ │ • AWS Secrets Manager   │
   │ • EC2 Instances       │ │ • SSM Parameter Store   │
   │ • RDS Instances       │ │ • Environment Variables │
   │ • Aurora Clusters     │ │ • Plain Text (Dev Only) │
   └───────────────────────┘ └──────────────────────────┘
```

## Key Features

### 1. Multi-Provider Support

The architecture supports various database deployment models:

- **Containers**: For local development and testing
- **EC2**: Self-managed databases on EC2 instances
- **RDS**: AWS-managed relational database service
- **Aurora**: AWS's cloud-native database service

### 2. Flexible Configuration Schema

```yaml
databases:
  - name: "database-identifier"
    type: "mysql|postgresql"
    provider: "container|ec2|rds|aurora"
    connection:
      # Provider-specific connection details
    credentials:
      # Flexible credential management
    monitoring:
      # Granular monitoring controls
    labels:
      # Custom metadata for filtering
```

### 3. Credential Management

Multiple credential sources supported:
- AWS Secrets Manager (recommended for production)
- SSM Parameter Store
- Environment variables
- Plain text (development only)

### 4. Environment-Specific Deployments

```
terraform/
├── modules/
│   ├── rds-mysql/
│   ├── rds-postgresql/
│   ├── aurora-mysql/
│   └── aurora-postgresql/
└── environments/
    ├── dev/          # Containers + LocalStack
    ├── staging/      # RDS instances
    └── production/   # Aurora clusters
```

## Monitoring Capabilities

### Standard Metrics
- Connection counts
- Query performance
- Resource utilization
- Replication lag

### Query Performance Monitoring
- Slow query analysis
- Query execution plans
- Wait event tracking
- Lock monitoring

### Provider-Specific Metrics
- **RDS**: CloudWatch integration, automated backups
- **Aurora**: Cluster-specific metrics, reader endpoint monitoring

## Implementation Flow

### 1. Discovery Phase
```bash
# Discover existing databases
./scripts/discover-databases.py \
  --regions us-east-1 us-west-2 \
  --tag-filter monitor=newrelic
```

### 2. Configuration Generation
The discovery script generates configuration in the enhanced format:
```yaml
mysql_databases:
  - name: "prod-mysql-rds"
    provider: "rds"
    connection:
      endpoint: "mydb.abc123.rds.amazonaws.com"
    # ... additional config
```

### 3. Infrastructure Deployment
```bash
# Deploy environment-specific infrastructure
cd terraform/environments/staging
terraform apply
```

### 4. Monitoring Configuration
Ansible templates automatically detect provider type and apply appropriate configuration:
```jinja2
{% if db.provider == 'rds' %}
  METRICS_SOURCE: rds
  COLLECT_RDS_METRICS: true
{% endif %}
```

## Security Architecture

### Network Security
- Private subnets for databases
- Security groups with least privilege
- VPC endpoints for AWS services

### Access Control
- IAM roles for EC2 instances
- Database-specific monitoring users
- Read-only permissions

### Secrets Management
```
┌──────────────┐     ┌─────────────────┐     ┌──────────────┐
│   Terraform  │────►│ Secrets Manager │◄────│ EC2 Instance │
└──────────────┘     └─────────────────┘     └──────────────┘
  Creates secrets      Stores passwords        Retrieves at runtime
```

## Scalability Considerations

### Horizontal Scaling
- Multiple monitoring instances per region
- Database discovery automation
- Tag-based resource selection

### Vertical Scaling
- Environment-specific instance sizing
- Configurable monitoring intervals
- Batch size limits

## Cost Optimization

### By Environment
- **Development**: LocalStack, containers (minimal cost)
- **Staging**: Single AZ, smaller instances
- **Production**: Multi-AZ, reserved instances

### By Feature
- Performance Insights: Enable only where needed
- Enhanced monitoring: Configurable intervals
- Backup retention: Environment-specific

## Migration Paths

### Container → RDS
1. Update provider in configuration
2. Migrate data using native tools
3. Update connection endpoints
4. Verify monitoring continuity

### RDS → Aurora
1. Use AWS migration tools
2. Update provider to 'aurora'
3. Add reader endpoint configuration
4. Enable Aurora-specific monitoring

## Extensibility

### Adding New Providers
1. Create Terraform module in `modules/`
2. Update configuration schema
3. Extend Ansible templates
4. Add to discovery script

### Custom Metrics
1. Define in `custom_metrics_query`
2. Provider-specific query files
3. Integration with New Relic Insights

## Best Practices

### Configuration Management
- Use version control for all configs
- Environment-specific variable files
- Automated validation

### Monitoring Strategy
- Start with standard metrics
- Enable query monitoring gradually
- Custom alerts per environment

### Security
- Rotate credentials regularly
- Use IAM roles over keys
- Encrypt data in transit and at rest

## Troubleshooting

### Common Issues
1. **Connection failures**: Check security groups and credentials
2. **Missing metrics**: Verify user permissions and agent configuration
3. **High costs**: Review instance types and monitoring intervals

### Debug Commands
```bash
# Check agent status
systemctl status newrelic-infra

# Validate configuration
newrelic-infra -validate_config

# Test database connectivity
mysql -h <endpoint> -u newrelic -p
```

## Future Enhancements

1. **Additional Providers**
   - Azure Database
   - Google Cloud SQL
   - MongoDB Atlas

2. **Advanced Features**
   - Automated anomaly detection
   - Predictive scaling
   - Cross-region replication monitoring

3. **Integration**
   - CI/CD pipeline integration
   - ChatOps notifications
   - Automated remediation