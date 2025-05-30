# Features

## What This Solution Provides

### Infrastructure Automation
- **Terraform**: Creates EC2 instance, security groups, IAM roles
- **Ansible**: Installs and configures New Relic agent
- **Scripts**: Automated deployment and verification

### Database Monitoring

#### MySQL
- Connection metrics (active, idle, max connections)
- Query performance via Performance Schema
- InnoDB buffer pool statistics
- Replication status and lag
- Lock wait analysis
- Table and index statistics
- Custom query metrics

#### PostgreSQL  
- Connection and transaction metrics
- Query performance via pg_stat_statements
- Cache hit ratios
- Vacuum and autovacuum stats
- Table bloat analysis
- Index usage statistics
- Lock monitoring

### Query Performance Monitoring

Both MySQL and PostgreSQL get detailed query insights:
- Top slow queries with execution stats
- Wait event analysis
- Query frequency and patterns
- Resource usage per query
- Full table scan detection
- Index usage recommendations

### Security Features
- IAM roles for EC2 (no hardcoded credentials)
- Secrets Manager/Parameter Store support
- TLS/SSL database connections
- Least privilege database users
- Encrypted EBS volumes

### Testing
- LocalStack for AWS simulation (free tier)
- MySQL and PostgreSQL test containers
- Mock New Relic API
- Unit and integration tests
- End-to-end deployment testing

### Additional Scripts

Beyond basic deployment, we include:
- `setup-verification.sh` - Comprehensive setup validation
- `test-db-connection.sh` - Pre-deployment database testing
- `validate-query-monitoring.sh` - Query monitoring validation
- `discover-databases.py` - Auto-discover RDS databases
- `transform-config.py` - Convert configurations

### Scaling Support
- Single instance handles up to 100 databases
- Multi-region deployment patterns
- Environment-based separation
- Configurable collection intervals

### What's NOT Included
- Auto-scaling (manual scaling only)
- Multi-AZ high availability
- Backup/restore automation
- Alert policy creation
- Dashboard creation