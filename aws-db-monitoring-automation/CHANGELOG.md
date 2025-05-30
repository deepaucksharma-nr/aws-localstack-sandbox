# Changelog

All notable changes to the New Relic Database Monitoring Automation project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Query performance monitoring for MySQL using Performance Schema
- Query performance monitoring for PostgreSQL using pg_stat_statements
- Custom query templates for business metrics
- LocalStack testing infrastructure
- Comprehensive documentation suite

### Changed
- Enhanced security with encrypted connections by default
- Improved error handling and retry logic
- Optimized collection intervals for better performance

### Fixed
- Database connection timeout issues
- Memory leak in long-running collections
- SSL certificate validation errors

## [1.0.0] - 2024-01-15

### Added
- Initial release of New Relic Database Monitoring Automation
- Terraform modules for AWS infrastructure provisioning
- Ansible playbooks for New Relic agent installation
- Support for MySQL 5.7, 8.0+ monitoring
- Support for PostgreSQL 11-15 monitoring
- Automated deployment script
- Basic testing framework
- Documentation for installation and configuration

### Security
- Least privilege IAM roles
- Encrypted EBS volumes
- Secure credential management with AWS Secrets Manager support

## [0.9.0] - 2023-12-01 (Beta)

### Added
- Beta release for internal testing
- Core monitoring functionality
- Basic MySQL and PostgreSQL support
- Manual configuration process

### Known Issues
- Limited to single region deployment
- No query performance monitoring
- Manual agent installation required

---

## Release Process

1. **Version Numbering**: We use semantic versioning (MAJOR.MINOR.PATCH)
   - MAJOR: Breaking changes
   - MINOR: New features (backward compatible)
   - PATCH: Bug fixes

2. **Release Cycle**: Monthly releases with patches as needed

3. **Support Policy**: 
   - Latest version: Full support
   - Previous minor version: Security updates only
   - Older versions: Community support

## Upgrade Guide

### From 0.9.0 to 1.0.0

1. **Infrastructure Changes**:
   ```bash
   # Update Terraform modules
   terraform init -upgrade
   terraform plan
   terraform apply
   ```

2. **Configuration Migration**:
   - Update database.yml to new format
   - Add query monitoring settings
   - Update credentials to use Secrets Manager

3. **Agent Update**:
   ```bash
   # Run Ansible playbook
   ansible-playbook playbooks/install-newrelic.yml --tags=upgrade
   ```

### Breaking Changes in 1.0.0

- Changed configuration file format
- Renamed several Terraform variables
- Updated minimum Ansible version to 2.9

## Deprecation Notices

- **v0.9.0**: Manual installation method deprecated, will be removed in v2.0.0
- **Single file configuration**: Moving to modular configuration in v2.0.0

---

For detailed upgrade instructions, see [UPGRADING.md](docs/UPGRADING.md)