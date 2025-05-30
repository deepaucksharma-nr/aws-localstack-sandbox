# Architecture

How this thing works.

## Overview

```
Your Databases → Monitoring Instance → New Relic
```

That's it. We spin up an EC2 instance, install the New Relic agent, and it talks to your databases.

## Components

### EC2 Monitoring Instance
- Runs New Relic Infrastructure agent
- Has MySQL and PostgreSQL integrations
- Polls your databases every 30-60 seconds
- Sends data to New Relic

### Network Setup
```
VPC
├── Private Subnet
│   ├── Monitoring Instance (EC2)
│   └── Your Databases
└── Security Groups
    ├── monitoring-sg (allows outbound HTTPS)
    └── database-sg (allows inbound from monitoring-sg)
```

### What Gets Collected

**Infrastructure:**
- CPU, memory, disk, network
- Running processes
- System logs

**MySQL:**
- Connections, queries/sec, slow queries
- InnoDB metrics, buffer pool stats
- Replication lag (if applicable)
- Query performance (via Performance Schema)

**PostgreSQL:**
- Connections, transactions, cache hit ratio
- Table/index stats, vacuum info
- Lock waits, deadlocks
- Query performance (via pg_stat_statements)

## Security

- Database credentials stored locally on monitoring instance
- Agent uses HTTPS to talk to New Relic
- Least privilege database users (read-only)
- Security groups restrict access

## Scaling

**Single Instance:** Good for ~100 databases

**Need more?**
- Deploy multiple monitoring instances
- Split by region/environment
- Each instance handles a subset

## Configuration Flow

1. Terraform creates the infrastructure
2. Ansible installs/configures the agent
3. Agent reads config files
4. Starts collecting and sending data

## File Structure

```
/etc/newrelic-infra.yml                     # Main agent config
/etc/newrelic-infra/integrations.d/
├── mysql-config.yml                        # MySQL databases
└── postgresql-config.yml                   # PostgreSQL databases
```

## Data Flow

1. Agent queries database every interval (30s default)
2. Collects metrics, formats as JSON
3. Batches and compresses data
4. POST to New Relic API over HTTPS
5. Shows up in your dashboards

## Failure Handling

- Can't reach database? Logs error, tries next interval
- Can't reach New Relic? Buffers locally, retries
- Instance dies? Auto-recovery enabled

## Cost Breakdown

- EC2 instance: ~$30-50/month (t3.medium)
- Network transfer: Minimal (compressed data)
- Storage: 30GB EBS included
- New Relic: Based on your plan

## Customization Points

- Collection intervals
- Which metrics to collect
- Custom SQL queries
- Instance size
- Multiple regions