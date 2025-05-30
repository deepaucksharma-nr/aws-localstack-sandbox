# Contributing to New Relic Database Monitoring Automation

First off, thanks for taking the time to contribute! 🎉

This document provides guidelines for contributing to the New Relic Database Monitoring Automation reference implementation. By participating in this project, you agree to abide by the [New Relic Community Code of Conduct](https://opensource.newrelic.com/code-of-conduct/).

## Table of Contents

- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Contribution Process](#contribution-process)
- [Style Guidelines](#style-guidelines)
- [Testing Requirements](#testing-requirements)
- [Documentation](#documentation)
- [Community](#community)

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce**
- **Expected behavior**
- **Actual behavior**
- **Environment details** (OS, versions, etc.)
- **Relevant logs** (sanitized of sensitive data)

### Suggesting Enhancements

Enhancement suggestions are welcome! Please provide:

- **Use case description**
- **Proposed solution**
- **Alternative solutions considered**
- **Additional context**

### Code Contributions

We love code contributions! Areas where you can help:

- 🐛 Bug fixes
- ✨ New features
- 📚 Documentation improvements
- 🧪 Test coverage
- 🔧 Performance optimizations

## Development Setup

### Prerequisites

```bash
# Required tools
- Terraform >= 1.0
- Ansible >= 2.9
- Python >= 3.8
- Docker & Docker Compose
- Git
```

### Local Development Environment

1. **Fork and Clone**
   ```bash
   git clone https://github.com/YOUR_USERNAME/aws-db-monitoring-automation.git
   cd aws-db-monitoring-automation
   ```

2. **Install Dependencies**
   ```bash
   # Python dependencies
   pip install -r test/requirements.txt
   
   # Pre-commit hooks
   pip install pre-commit
   pre-commit install
   ```

3. **Start Test Environment**
   ```bash
   make start
   ```

4. **Run Tests**
   ```bash
   make test
   ```

## Contribution Process

### 1. Create a Branch

```bash
# Feature branch
git checkout -b feature/your-feature-name

# Bug fix branch
git checkout -b fix/issue-description
```

### 2. Make Your Changes

- Write clean, self-documenting code
- Follow existing patterns and conventions
- Add tests for new functionality
- Update documentation as needed

### 3. Test Your Changes

```bash
# Run all tests
make test

# Run specific test suite
make test-unit
make test-integration

# Lint your code
make lint
```

### 4. Commit Your Changes

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```bash
# Format: <type>(<scope>): <subject>

# Examples:
git commit -m "feat(terraform): add support for RDS instances"
git commit -m "fix(ansible): correct MySQL permission grants"
git commit -m "docs(readme): update installation instructions"
git commit -m "test(integration): add PostgreSQL connection tests"
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Test additions or changes
- `chore`: Build process or auxiliary tool changes

### 5. Push and Create Pull Request

```bash
git push origin your-branch-name
```

Then create a Pull Request with:
- Clear title and description
- Reference to any related issues
- Summary of changes
- Testing performed

## Style Guidelines

### Terraform

```hcl
# Use consistent formatting
terraform fmt -recursive

# Naming conventions
resource "aws_instance" "monitoring" {  # Use descriptive names
  # Group arguments logically
  # Required arguments first
  ami           = var.ami_id
  instance_type = var.instance_type
  
  # Optional arguments
  monitoring = true
  
  # Nested blocks
  root_block_device {
    volume_size = 30
    encrypted   = true
  }
  
  # Tags last
  tags = {
    Name        = "${var.environment}-monitoring"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

### Ansible

```yaml
# Use YAML syntax, not JSON
# Consistent indentation (2 spaces)
- name: Clear, descriptive task names
  package:
    name: "{{ item }}"
    state: present
  loop:
    - package1
    - package2
  when: ansible_os_family == "RedHat"
  tags:
    - packages
    - install
```

### Python

```python
# Follow PEP 8
# Use type hints where applicable
def process_database_config(config: dict) -> list:
    """
    Process database configuration and return connection list.
    
    Args:
        config: Database configuration dictionary
        
    Returns:
        List of database connection dictionaries
    """
    connections = []
    # Implementation
    return connections
```

## Testing Requirements

### Test Coverage

All new features must include:
- Unit tests (minimum 80% coverage)
- Integration tests for external interactions
- Documentation updates
- Example configurations

### Test Structure

```python
# test/unit/test_feature.py
import pytest

class TestFeature:
    """Test new feature functionality."""
    
    def test_normal_operation(self):
        """Test feature under normal conditions."""
        # Arrange
        # Act
        # Assert
        
    def test_error_handling(self):
        """Test feature error handling."""
        # Test edge cases and errors
```

### Running Tests

```bash
# Local testing
make test

# With coverage
pytest --cov=. --cov-report=html

# Specific tests
pytest test/unit/test_configuration.py -v
```

## Documentation

### Code Documentation

- Add docstrings to all functions/classes
- Include inline comments for complex logic
- Update README for user-facing changes

### Documentation Updates

When updating documentation:
1. Use clear, concise language
2. Include code examples
3. Update table of contents if needed
4. Check links are valid

## Release Process

We use semantic versioning (MAJOR.MINOR.PATCH):

- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes

Releases are automated via GitHub Actions when tags are pushed:

```bash
git tag -a v1.2.3 -m "Release version 1.2.3"
git push origin v1.2.3
```

## Community

### Getting Help

- 💬 [Explorers Hub](https://discuss.newrelic.com)
- 📧 [Email](opensource+aws-db-monitoring@newrelic.com)
- 🐦 [Twitter](https://twitter.com/newrelic)

### Recognition

Contributors are recognized in:
- [CONTRIBUTORS.md](CONTRIBUTORS.md)
- Release notes
- Community highlights

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.

---

**Thank you for contributing to New Relic Database Monitoring Automation!** 🚀