# New Relic Database Monitoring Reference Architecture

<div align="center">
  <img src="https://newrelic.com/assets/newrelic/source/NewRelic-logo-square.png" alt="New Relic" width="100">
  
  [![New Relic Experimental](https://img.shields.io/badge/New%20Relic-Experimental-blue)](https://opensource.newrelic.com/oss-category/#new-relic-experimental)
  [![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
  [![Terraform](https://img.shields.io/badge/Terraform->=1.0-623ce4)](https://www.terraform.io)
  [![Ansible](https://img.shields.io/badge/Ansible->=2.9-ee0000)](https://www.ansible.com)
  
  **Production-ready automation for deploying New Relic database monitoring at scale**
  
  [Quick Start](QUICK_START.md) • [Documentation](docs/) • [Contributing](CONTRIBUTING.md) • [Support](#support)
</div>

## 🚀 Overview

This reference architecture provides a complete, automated solution for deploying New Relic Infrastructure monitoring with database integrations (MySQL and PostgreSQL) on AWS. Developed and maintained by the New Relic team, it demonstrates best practices for infrastructure automation, security, and observability.

### ✨ Key Features

- **🔧 Infrastructure as Code**: Fully automated deployment using Terraform and Ansible
- **📊 Query Performance Monitoring**: Deep insights into slow queries, wait events, and database performance
- **🔒 Security First**: Encrypted connections, least-privilege access, credential vaulting support
- **🧪 Comprehensive Testing**: LocalStack integration for cost-free testing and validation
- **📈 Production Ready**: Battle-tested patterns for monitoring hundreds of databases
- **🎯 Multi-Database Support**: MySQL 5.7/8.0+, PostgreSQL 11-15, Amazon RDS, Aurora

### 💡 Use Cases

- **Enterprise Fleet Monitoring**: Deploy consistent monitoring across your entire database infrastructure
- **DevOps Automation**: Integrate database monitoring into your CI/CD pipelines
- **Migration Projects**: Monitor performance during database migrations
- **Compliance Requirements**: Track access patterns and performance for audit requirements

## 📋 Prerequisites

- AWS Account with appropriate IAM permissions
- New Relic account with Infrastructure Pro subscription
- Existing VPC and subnet infrastructure
- Basic knowledge of Terraform and Ansible

## 🏃 Quick Start

Get monitoring deployed in under 10 minutes:

```bash
# Clone the repository
git clone https://github.com/newrelic/aws-db-monitoring-automation.git
cd aws-db-monitoring-automation

# Configure your environment
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp config/databases.example.yml config/databases.yml

# Edit configurations with your values
nano terraform/terraform.tfvars
nano config/databases.yml

# Deploy!
./scripts/deploy-monitoring.sh -k ~/.ssh/your-aws-key.pem
```

See the [Quick Start Guide](QUICK_START.md) for detailed instructions.

## 🏗️ Architecture

This solution deploys a monitoring infrastructure that includes:

- **EC2 Monitoring Instance**: Hosts the New Relic Infrastructure agent and database integrations
- **Security Groups**: Network isolation with least-privilege access
- **IAM Roles**: Secure credential management without long-lived keys
- **New Relic Integrations**: MySQL and PostgreSQL monitoring with query performance insights

<details>
<summary>View Architecture Diagram</summary>

```
┌─────────────────────────────────────────┐
│          New Relic One Platform          │
│  ┌─────────┐ ┌──────────┐ ┌──────────┐ │
│  │ Dashboards││ Alerts   ││ Insights  │ │
│  └─────────┘ └──────────┘ └──────────┘ │
└────────────────────┬────────────────────┘
                     │ HTTPS
        ┌────────────┴────────────┐
        │   Monitoring Instance   │
        │  ┌─────────────────┐   │
        │  │ NR Infra Agent  │   │
        │  │ + DB Integrations│   │
        │  └────────┬────────┘   │
        └───────────┼─────────────┘
                    │
     ┌──────────────┴──────────────┐
     │                             │
┌────┴────┐                 ┌─────┴────┐
│ MySQL   │                 │PostgreSQL│
│Databases│                 │Databases │
└─────────┘                 └──────────┘
```
</details>

## 📊 What Gets Monitored?

### Infrastructure Metrics
- CPU, Memory, Disk, Network utilization
- Process monitoring
- System events and logs

### Database Metrics

<table>
<tr>
<td>

**MySQL**
- Connection statistics
- Query performance (via Performance Schema)
- InnoDB metrics
- Replication status
- Lock contention
- Buffer pool efficiency
- Table and index statistics

</td>
<td>

**PostgreSQL**
- Connection and transaction rates
- Query performance (via pg_stat_statements)
- Cache hit ratios
- Vacuum and autovacuum metrics
- Lock statistics
- Index usage and efficiency
- Replication lag

</td>
</tr>
</table>

### Query Performance Insights
- Top slow queries with execution plans
- Wait event analysis
- Query frequency and patterns
- Resource consumption per query
- Historical query performance trends

## 🛠️ Configuration

### Basic Configuration

```yaml
# config/databases.yml
newrelic_license_key: "YOUR_LICENSE_KEY"
newrelic_account_id: "YOUR_ACCOUNT_ID"

mysql_databases:
  - host: mysql-prod.example.com
    port: 3306
    user: newrelic
    password: "secure_password"
    enable_query_monitoring: true
    custom_labels:
      environment: production
      team: platform

postgresql_databases:
  - host: postgres-prod.example.com
    port: 5432
    user: newrelic
    password: "secure_password"
    database: postgres
    enable_query_monitoring: true
    sslmode: require
```

### Advanced Features

- **Custom Metrics**: Define business-specific queries
- **Label Strategy**: Organize resources with custom labels
- **Collection Intervals**: Optimize for your workload
- **SSL/TLS**: Secure database connections

See [Configuration Guide](docs/CONFIGURATION.md) for all options.

## 🧪 Testing

This project includes comprehensive testing with LocalStack:

```bash
# Start local test environment
make start

# Run all tests
make test

# Run specific test suites
make test-unit
make test-integration
make test-e2e

# Stop test environment
make stop
```

See [Testing Guide](TESTING.md) for detailed information.

## 📚 Documentation

- 📖 [Quick Start Guide](QUICK_START.md) - Get up and running quickly
- 🏛️ [Architecture Overview](docs/ARCHITECTURE.md) - Deep dive into the solution design
- 🔐 [Best Practices](docs/BEST_PRACTICES.md) - Security, performance, and operational guidance
- 🔧 [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions
- 🧪 [Testing Guide](TESTING.md) - Comprehensive testing documentation
- 📊 [Dashboard Templates](docs/DASHBOARDS.md) - Pre-built New Relic dashboards
- 🚨 [Alerting Guide](docs/ALERTING.md) - Alert policy recommendations

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on:

- Code of Conduct
- Development setup
- Submitting pull requests
- Style guidelines

## 🆘 Support

### Community Support

- 💬 [New Relic Explorers Hub](https://discuss.newrelic.com) - Community forum
- 📺 [Video Tutorials](https://youtube.com/newrelic) - YouTube channel
- 📚 [Documentation](https://docs.newrelic.com) - Official docs

### Commercial Support

- 🎫 [Support Portal](https://support.newrelic.com) - For customers with support plans
- 📧 [Contact Sales](https://newrelic.com/contact-sales) - For licensing questions

### Reporting Issues

Found a bug? Have a feature request?

1. Check [existing issues](https://github.com/newrelic/aws-db-monitoring-automation/issues)
2. Create a [new issue](https://github.com/newrelic/aws-db-monitoring-automation/issues/new) with:
   - Clear description
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details

## 📜 License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- New Relic Infrastructure team
- New Relic Database monitoring team
- Open source community contributors
- All our users and testers

---

<div align="center">
  <b>Built with ❤️ by the New Relic team</b>
  <br>
  <a href="https://newrelic.com">newrelic.com</a> • 
  <a href="https://twitter.com/newrelic">@newrelic</a> • 
  <a href="https://github.com/newrelic">GitHub</a>
</div>