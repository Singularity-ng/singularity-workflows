# QuantumFlow Reference Documentation

This directory contains in-depth reference documentation for QuantumFlow developers and users.

## Quick Navigation

### For New Users
- Start with [Getting Started Guide](../GETTING_STARTED.md) in the root
- Then read [Architecture Overview](../ARCHITECTURE.md) for technical understanding

### For Developers Contributing Code
- Read [Contributing Guide](../CONTRIBUTING.md) for development workflow
- Check [Dynamic Workflows Guide](DYNAMIC_WORKFLOWS_GUIDE.md) for workflow definition patterns
- See [Dialyzer Type Fixes](DIALYZER_TYPE_FIXES.md) for type system quirks

### For Understanding Design
- [PGFLOW_REFERENCE.md](PGFLOW_REFERENCE.md) - Complete API reference
- [PGFLOW_DEV_FEATURE_COMPARISON.md](PGFLOW_DEV_FEATURE_COMPARISON.md) - How QuantumFlow compares to QuantumFlow
- [SECURITY_AUDIT.md](SECURITY_AUDIT.md) - Security considerations and audit results

### For Operational Deployment
- [TIMEOUT_CHANGES_SUMMARY.md](TIMEOUT_CHANGES_SUMMARY.md) - Task timeout handling
- [INPUT_VALIDATION.md](INPUT_VALIDATION.md) - Input validation patterns
- [GITHUB_SETUP.md](GITHUB_SETUP.md) - GitHub Actions CI/CD setup

## Document Overview

### DYNAMIC_WORKFLOWS_GUIDE.md
Advanced patterns for defining workflows:
- Dynamic workflow generation at runtime
- Conditional step execution
- Map/reduce style parallel operations
- Error handling and retries

### PGFLOW_REFERENCE.md
Complete API reference:
- Module documentation
- Function signatures
- Type specifications
- Return value documentation

### PGFLOW_DEV_FEATURE_COMPARISON.md
Detailed comparison with original QuantumFlow:
- Feature parity matrix
- Performance comparisons
- Architectural differences
- Migration guide from QuantumFlow

### SECURITY_AUDIT.md
Security analysis and findings:
- Database security
- Input validation
- SQL injection prevention
- Access control patterns

### TIMEOUT_CHANGES_SUMMARY.md
Task execution timeouts:
- Visibility timeout (VT) parameter
- Task retry behavior
- Timeout configuration
- Edge cases and gotchas

### INPUT_VALIDATION.md
Input validation framework:
- Schema validation
- Type checking
- Error messages
- Custom validators

### GITHUB_SETUP.md
GitHub Actions CI/CD:
- Automated testing
- Code quality checks
- Release automation
- Deployment workflows

## Contributing to Documentation

When adding new features to QuantumFlow:

1. Update the relevant reference document
2. Add examples to [DYNAMIC_WORKFLOWS_GUIDE.md](DYNAMIC_WORKFLOWS_GUIDE.md) if applicable
3. Update [PGFLOW_REFERENCE.md](PGFLOW_REFERENCE.md) with new APIs
4. Note any security implications in [SECURITY_AUDIT.md](SECURITY_AUDIT.md)
5. Document any configuration changes in [TIMEOUT_CHANGES_SUMMARY.md](TIMEOUT_CHANGES_SUMMARY.md)

## Keeping Docs in Sync

- Reference docs are updated with code changes
- Examples are tested as part of CI/CD
- Generated API docs come from @doc comments in code
- Architecture decisions are documented as they're made

## Questions or Issues?

- Check [ARCHITECTURE.md](../ARCHITECTURE.md) for technical details
- See [GETTING_STARTED.md](../GETTING_STARTED.md) for usage questions
- Read [CONTRIBUTING.md](../CONTRIBUTING.md) for development help
- Open a GitHub issue for bugs or feature requests
