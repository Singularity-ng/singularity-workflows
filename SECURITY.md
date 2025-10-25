# Security Policy

## Reporting a Vulnerability

Please do NOT open a public GitHub issue for security vulnerabilities.

Instead, report security concerns privately to: **mhugo@hey.com**

Include in your report:
- Description of the vulnerability
- Steps to reproduce (if applicable)
- Potential impact and severity
- Suggested fix (if you have one)

**We will respond within 48 hours** and work on a fix in a private security advisory.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | ✅ Yes   |

## Security Considerations

ExPgflow is designed for workflow orchestration in trusted environments. Here are important security practices:

### Database Security

1. **Connection Security**
   - Always use SSL/TLS for PostgreSQL connections
   - Use strong, unique credentials for database access
   - Restrict database access to authorized services only

2. **Access Control**
   - Database user should have minimal required permissions
   - Use separate credentials for different environments (dev, test, prod)
   - Regularly rotate database passwords

### pgmq Queue Security

1. **Queue Protection**
   - pgmq queue should not be publicly accessible
   - Only authorized services should read/write to the queue
   - Use PostgreSQL role-based access control (RBAC)

2. **Message Content**
   - Don't include secrets in workflow messages
   - Use secure secret management (e.g., environment variables, vaults)
   - Sanitize user input before passing to workflows

### Workflow Definition Security

1. **Definition Validation**
   - Validate workflow definitions before execution
   - Use allowlists for permitted commands/operations
   - Prevent injection attacks in step arguments

2. **Step Execution**
   - Implement timeouts for long-running steps
   - Use isolated execution contexts where possible
   - Log all step executions for audit trails

### Input Validation

1. **Workflow Input**
   - Validate all input against expected schema
   - Reject unexpectedly large inputs
   - Sanitize string inputs to prevent injection

2. **Step Arguments**
   - Validate step-specific arguments
   - Prevent command injection in step commands
   - Use parameterized approaches where possible

### Deployment Security

1. **Network Security**
   - Run in isolated network (VPC, private subnet)
   - Restrict outbound connections to required services
   - Use firewalls to control access

2. **Authentication & Authorization**
   - Authenticate workflow requests
   - Authorize based on user/service permissions
   - Log access attempts and authorization decisions

3. **Monitoring & Alerting**
   - Monitor for unusual workflow execution patterns
   - Alert on failed step executions
   - Track resource usage and set limits

### Data Protection

1. **Data in Transit**
   - Use TLS 1.2+ for all connections
   - Verify certificate validity

2. **Data at Rest**
   - Encrypt sensitive data in database
   - Use PostgreSQL's pgcrypto extension if needed
   - Protect backup files

3. **Data Retention**
   - Define workflow execution retention policy
   - Delete completed runs after retention period
   - Sanitize logs to remove sensitive data

## Security Audit

ExPgflow has been reviewed for common vulnerabilities. See [docs/SECURITY_AUDIT.md](docs/SECURITY_AUDIT.md) for detailed findings.

## Dependencies

ExPgflow uses well-maintained Elixir packages. Dependency security is monitored with:
- `mix deps.audit` - Check for known vulnerabilities
- Regular dependency updates
- GitHub Dependabot alerts

To check dependencies:
```bash
mix deps.audit
```

## Security Best Practices

### Do's ✅
- ✅ Use strong database credentials
- ✅ Enable TLS for database connections
- ✅ Validate all workflow inputs
- ✅ Implement timeouts for steps
- ✅ Log all executions for audit trails
- ✅ Regularly update dependencies
- ✅ Isolate workflows in sandboxed environment
- ✅ Use environment variables for secrets

### Don'ts ❌
- ❌ Don't hardcode secrets in code
- ❌ Don't expose pgmq to public internet
- ❌ Don't skip input validation
- ❌ Don't run with excessive permissions
- ❌ Don't disable TLS
- ❌ Don't ignore dependency vulnerabilities
- ❌ Don't log sensitive data
- ❌ Don't run untrusted workflow definitions

## Questions?

For security-related questions that aren't vulnerabilities, open an issue with the `security` label.

---

Last Updated: 2025-01-10
ExPgflow Version: 0.1.0
