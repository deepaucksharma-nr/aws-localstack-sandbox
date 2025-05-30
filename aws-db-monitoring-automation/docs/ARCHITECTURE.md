# Architecture Documentation

## System Architecture Overview

This reference implementation follows a modular, cloud-native architecture designed for scalability, security, and maintainability.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           New Relic One Platform                         │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  ┌───────────────┐ │
│  │Infrastructure│  │  Database    │  │   Query    │  │    Custom     │ │
│  │  Dashboard   │  │  Monitoring  │  │Performance │  │  Dashboards   │ │
│  └─────────────┘  └──────────────┘  └────────────┘  └───────────────┘ │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │ HTTPS/TLS
                                  │
┌─────────────────────────────────┴───────────────────────────────────────┐
│                          Monitoring Infrastructure                        │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    EC2 Monitoring Instance                       │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐ │   │
│  │  │  New Relic  │  │MySQL/Postgres│  │   Custom Metrics      │ │   │
│  │  │Infrastructure│  │ Integrations │  │   Query Configs       │ │   │
│  │  │    Agent    │  │              │  │                       │ │   │
│  │  └──────┬──────┘  └──────┬───────┘  └──────────┬────────────┘ │   │
│  │         │                 │                      │              │   │
│  │         └─────────────────┴──────────────────────┘              │   │
│  │                           │                                      │   │
│  └───────────────────────────┼──────────────────────────────────────┘   │
│                              │ Secure Database Connections              │
└──────────────────────────────┼──────────────────────────────────────────┘
                               │
┌──────────────────────────────┴──────────────────────────────────────────┐
│                          Database Infrastructure                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │   MySQL Primary │  │ MySQL Replicas  │  │   PostgreSQL    │         │
│  │                 │  │                 │  │    Cluster      │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
└──────────────────────────────────────────────────────────────────────────┘
```

## Component Architecture

### 1. Infrastructure Layer (Terraform)

```hcl
Infrastructure Components:
├── Compute
│   ├── EC2 Instance (Monitoring Server)
│   ├── Instance Profile (IAM Role)
│   └── User Data (Bootstrap Script)
├── Networking
│   ├── Security Group
│   ├── Network ACLs
│   └── VPC Endpoints (Optional)
├── Storage
│   ├── EBS Volumes (Encrypted)
│   └── S3 Buckets (Config Backup)
└── Security
    ├── KMS Keys
    ├── Secrets Manager
    └── SSM Parameters
```

**Key Design Decisions:**
- **Single Instance Pattern**: One monitoring instance can handle 100+ databases
- **Immutable Infrastructure**: Instances are replaced, not updated
- **Secure by Default**: All storage encrypted, minimal network exposure
- **Cloud-Native**: Leverages AWS services for security and scalability

### 2. Configuration Management Layer (Ansible)

```yaml
Ansible Architecture:
├── Inventory Management
│   ├── Dynamic Inventory
│   ├── Group Variables
│   └── Host Variables
├── Playbooks
│   ├── Site.yml (Main Orchestrator)
│   ├── Install-NewRelic.yml
│   └── Configure-Databases.yml
├── Roles
│   ├── newrelic-infrastructure
│   ├── mysql-integration
│   └── postgresql-integration
└── Templates
    ├── Agent Configuration
    ├── Integration Configs
    └── Custom Queries
```

**Configuration Flow:**
1. **Agent Installation**: Repository setup, package installation, service enablement
2. **Integration Setup**: Database-specific packages and configurations
3. **Custom Metrics**: Query definitions and collection intervals
4. **Service Validation**: Health checks and connectivity tests

### 3. Monitoring Configuration

#### Database Credentials Management
```yaml
Credential Flow:
1. AWS Secrets Manager / Parameter Store
   └── Encrypted at rest
2. Ansible Vault (Alternative)
   └── Encrypted in repository
3. Runtime Injection
   └── Environment variables
4. New Relic Agent
   └── Secure transmission
```

#### Query Performance Monitoring Architecture

**PostgreSQL Implementation:**
```sql
Components:
├── pg_stat_statements
│   ├── Query normalization
│   ├── Execution statistics
│   └── Resource consumption
├── pg_stat_database
│   ├── Connection metrics
│   ├── Transaction rates
│   └── Cache hit ratios
└── Custom Queries
    ├── Long running queries
    ├── Lock analysis
    └── Index usage
```

**MySQL Implementation:**
```sql
Components:
├── performance_schema
│   ├── Statement events
│   ├── Wait events
│   └── Stage events
├── information_schema
│   ├── Table statistics
│   ├── Index statistics
│   └── Engine status
└── Custom Queries
    ├── Slow query analysis
    ├── Lock wait detection
    └── Replication status
```

### 4. Data Flow Architecture

```mermaid
sequenceDiagram
    participant DB as Database
    participant Agent as NR Agent
    participant Integration as DB Integration
    participant API as NR API
    participant Platform as NR Platform

    Integration->>DB: Execute monitoring queries
    DB-->>Integration: Return metrics
    Integration->>Agent: Send structured data
    Agent->>API: HTTPS POST (compressed)
    API-->>Platform: Process and store
    Platform-->>Platform: Generate insights
```

**Data Collection Intervals:**
- Infrastructure Metrics: 15 seconds
- Database Metrics: 30-60 seconds
- Query Performance: 60 seconds
- Custom Metrics: Configurable

### 5. Security Architecture

```
Security Layers:
├── Network Security
│   ├── Private Subnets
│   ├── Security Groups (Least Privilege)
│   ├── NACLs (Defense in Depth)
│   └── VPC Endpoints (Private Connectivity)
├── Identity & Access
│   ├── IAM Roles (No Long-term Credentials)
│   ├── Database Users (Read-only)
│   ├── MFA Requirements
│   └── Audit Logging
├── Data Protection
│   ├── Encryption in Transit (TLS 1.2+)
│   ├── Encryption at Rest (KMS)
│   ├── Secure Credential Storage
│   └── Data Retention Policies
└── Compliance
    ├── CIS Benchmarks
    ├── AWS Well-Architected
    ├── SOC2 Controls
    └── GDPR Compliance
```

### 6. Scalability Patterns

#### Horizontal Scaling
```yaml
Multi-Instance Deployment:
├── Region 1
│   ├── Monitoring Instance A (Databases 1-50)
│   └── Monitoring Instance B (Databases 51-100)
└── Region 2
    ├── Monitoring Instance C (Databases 101-150)
    └── Monitoring Instance D (Databases 151-200)
```

#### Federation Pattern
```yaml
Centralized Management:
├── Central Config Repository
│   └── Git-based Configuration
├── Regional Deployments
│   ├── Terraform Workspaces
│   └── Regional State Files
└── Global Visibility
    └── New Relic Cross-Account
```

### 7. High Availability Design

```
HA Components:
├── Monitoring Infrastructure
│   ├── Multi-AZ Deployment
│   ├── Auto-recovery (EC2)
│   └── Configuration Backup
├── Data Collection
│   ├── Local Buffering
│   ├── Retry Logic
│   └── Circuit Breakers
└── Operational
    ├── Automated Failover
    ├── Health Monitoring
    └── Alerting
```

### 8. Testing Architecture

```
Test Pyramid:
├── Unit Tests (70%)
│   ├── Configuration Validation
│   ├── Template Rendering
│   └── Utility Functions
├── Integration Tests (20%)
│   ├── Service Connectivity
│   ├── API Contracts
│   └── Database Queries
└── E2E Tests (10%)
    ├── Full Deployment
    ├── Data Flow Verification
    └── Monitoring Validation
```

## Technology Stack

### Core Technologies
- **Infrastructure**: Terraform v1.0+
- **Configuration**: Ansible 2.9+
- **Monitoring**: New Relic Infrastructure Agent
- **Languages**: Python 3.8+, Bash, HCL
- **Testing**: Pytest, LocalStack, Docker

### AWS Services
- **Compute**: EC2, Systems Manager
- **Networking**: VPC, Security Groups
- **Security**: IAM, Secrets Manager, KMS
- **Storage**: EBS, S3

### Database Support
- **MySQL**: 5.7, 8.0+
- **PostgreSQL**: 11, 12, 13, 14, 15+
- **MariaDB**: 10.3+
- **Amazon RDS**: All variants
- **Amazon Aurora**: MySQL/PostgreSQL compatible

## Performance Specifications

### Monitoring Capacity
- **Single Instance**: Up to 100 databases
- **Memory Usage**: ~500MB base + 10MB per database
- **CPU Usage**: <5% idle, <20% during collection
- **Network**: ~1KB/s per database continuous

### Collection Performance
- **Query Execution**: <100ms per query
- **Batch Processing**: 10 databases concurrent
- **API Transmission**: Compressed, batched
- **Error Recovery**: Exponential backoff

## Deployment Patterns

### 1. Single Region, Multiple Databases
Best for: Small to medium deployments
```
Region
└── Single Monitoring Instance
    └── All Databases
```

### 2. Multi-Region, Distributed
Best for: Large, distributed deployments
```
Region A          Region B
├── Instance 1    ├── Instance 3
└── Instance 2    └── Instance 4
```

### 3. Hybrid Cloud
Best for: Mixed on-premises and cloud
```
AWS Cloud         On-Premises
├── Instance A    ├── Instance X
└── Instance B    └── Instance Y
                  (Connected via VPN/Direct Connect)
```

## Operational Considerations

### Backup and Recovery
- Configuration backed up to S3
- State files versioned
- Database credentials in Secrets Manager
- Recovery RTO: <15 minutes

### Monitoring the Monitors
- Self-monitoring via New Relic
- CloudWatch metrics integration
- Health check endpoints
- Automated alerting

### Maintenance Windows
- Rolling updates supported
- Zero-downtime deployment
- Canary deployment pattern
- Automated rollback

---

*This architecture is designed to be flexible, secure, and scalable. It represents New Relic's recommended patterns for production database monitoring deployments.*