# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, please send an email to the project maintainers with:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Security Best Practices for Deployment

This platform handles cost data and budget configurations. Follow these practices:

1. **Never commit secrets** — Use Azure Key Vault or environment variables for:
   - Cosmos DB keys
   - Function App host keys
   - Log Analytics shared keys
   - Teams webhook URLs

2. **Use Managed Identity** — The Function App and Logic Apps use system-assigned managed identity. Avoid shared key authentication where possible.

3. **Minimal RBAC** — Grant only the roles documented in the deployment guide. Do not use Owner role for day-to-day operations.

4. **Private Endpoints** — For production deployments, enable private endpoints on Cosmos DB and Storage Account.

5. **Rotate keys** — Rotate Function App keys and Cosmos DB keys on a regular schedule.

## Supported Versions

| Version | Supported |
|---------|-----------|
| main branch | Yes |
| All other branches | No |
