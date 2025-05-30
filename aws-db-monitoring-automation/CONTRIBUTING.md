# Contributing

Want to help? Great!

## Quick Setup

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/aws-db-monitoring-automation.git
cd aws-db-monitoring-automation

# Install test dependencies
pip install -r test/requirements.txt

# Run tests
make test
```

## Making Changes

1. Create a branch: `git checkout -b fix/whatever`
2. Make your changes
3. Run tests: `make test`
4. Push and create a PR

## Code Style

- Terraform: Run `terraform fmt`
- Python: Follow PEP 8
- YAML: 2 spaces, not tabs
- Keep it simple

## Testing

```bash
# Run everything
make test

# Just unit tests
make test-unit

# Test with LocalStack
make start
make test-integration
make stop
```

## Commit Messages

Keep them short and clear:
- `fix: correct MySQL permission grants`
- `feat: add RDS support`
- `docs: update troubleshooting guide`

## What We Need Help With

- Bug fixes
- More database types (MariaDB, Aurora)
- Better error messages
- Documentation improvements
- Test coverage

## Pull Request Checklist

- [ ] Tests pass
- [ ] Code formatted
- [ ] Docs updated (if needed)
- [ ] Commit message makes sense

## Questions?

- Open an issue
- Ask in https://discuss.newrelic.com

Thanks for contributing!