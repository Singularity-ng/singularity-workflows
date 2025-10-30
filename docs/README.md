# QuantumFlow Reference Documentation

This directory contains in-depth reference documentation for QuantumFlow developers and users.

## Quick Navigation

### For New Users
- Start with [Getting Started Guide](../GETTING_STARTED.md) in the root
- Then read [Architecture Overview](../ARCHITECTURE.md) for technical understanding

### For Developers Contributing Code
- Read [Contributing Guide](../CONTRIBUTING.md) for development workflow
- Check [Dynamic Workflows Guide](DYNAMIC_WORKFLOWS_GUIDE.md) for workflow definition patterns
- Review [Testing Guide](../TESTING_GUIDE.md) for test patterns

### For Understanding Design
- [QUANTUM_FLOW_REFERENCE.md](QUANTUM_FLOW_REFERENCE.md) - Complete API reference
- [SECURITY_AUDIT.md](SECURITY_AUDIT.md) - Security considerations and audit results
- [Architecture Documentation](architecture_diagrams.md) - Visual architecture diagrams

### For Operational Deployment
- [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md) - Production deployment instructions
- [INPUT_VALIDATION.md](INPUT_VALIDATION.md) - Input validation patterns
- [GITHUB_REPOSITORY_SETUP.md](GITHUB_REPOSITORY_SETUP.md) - GitHub repository setup

## Document Overview

### DYNAMIC_WORKFLOWS_GUIDE.md
Advanced patterns for defining workflows:
- Dynamic workflow generation at runtime
- Conditional step execution
- Map/reduce style parallel operations
- Error handling and retries

### QUANTUM_FLOW_REFERENCE.md
Complete API reference:
- Module documentation
- Function signatures
- Type specifications
- Return value documentation

### DYNAMIC_WORKFLOWS_GUIDE.md
Advanced patterns for defining workflows:
- Dynamic workflow generation at runtime
- Conditional step execution
- Map/reduce style parallel operations
- Error handling and retries

### SECURITY_AUDIT.md
Security analysis and findings:
- Database security
- Input validation
- SQL injection prevention
- Access control patterns

### INPUT_VALIDATION.md
Input validation framework:
- Schema validation
- Type checking
- Error messages
- Custom validators

## Contributing to Documentation

When adding new features to QuantumFlow:

1. Update the relevant reference document
2. Add examples to [DYNAMIC_WORKFLOWS_GUIDE.md](DYNAMIC_WORKFLOWS_GUIDE.md) if applicable
3. Update [QUANTUM_FLOW_REFERENCE.md](QUANTUM_FLOW_REFERENCE.md) with new APIs
4. Note any security implications in [SECURITY_AUDIT.md](SECURITY_AUDIT.md)
5. Update [INPUT_VALIDATION.md](INPUT_VALIDATION.md) if validation patterns change

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
