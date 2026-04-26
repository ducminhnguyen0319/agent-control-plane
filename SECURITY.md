# Security Policy

## Reporting a Vulnerability

We take the security of Agent Control Plane (ACP) seriously. If you discover a security vulnerability, please follow these steps:

### 🔒 Private Disclosure (Preferred)

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, please report security issues privately via one of these methods:

1. **GitHub Security Advisories** (Preferred)
   - Go to [GitHub Security Advisories](https://github.com/ducminhnguyen0319/agent-control-plane/security/advisories)
   - Click "New draft security advisory"
   - Fill in the details and submit

2. **Email**
   - Send an email to: security@agent-control-plane.dev
   - Include "SECURITY" in the subject line
   - Provide detailed description and reproduction steps

### What to Include

Please include the following in your report:
- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Potential impact
- Suggested fix (if any)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 1 week
- **Fix release**: Within 2 weeks for critical issues, 4 weeks for others

## Supported Versions

We provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 0.7.x   | :white_check_mark: |
| 0.6.x   | :white_check_mark: |
| < 0.6   | :x:                |

## Security Best Practices

When using ACP:

1. **Keep dependencies updated**
   ```bash
   npm update agent-control-plane
   ```

2. **Review worker permissions**
   - ACP workers run with the same permissions as the user who started them
   - Use dedicated service accounts in production
   - Limit file system access where possible

3. **Secure your forge credentials**
   - Use fine-grained personal access tokens (GitHub)
   - Rotate tokens regularly
   - Never commit tokens to repositories

4. **Sandbox worker execution**
   - Consider running ACP in a container or isolated environment
   - Use firewall rules to limit network access
   - Monitor worker activity via dashboard

5. **Audit dependencies**
   ```bash
   npm audit
   npm audit fix
   ```

## Known Security Considerations

### Worker Backend Access
ACP delegates coding tasks to worker backends (codex, claude, ollama, etc.). These backends:
- Have access to your repository files
- Can execute arbitrary code via the agent
- May send data to external APIs (for cloud-based backends)

**Mitigation**: Use local backends (ollama) for sensitive repositories.

### Forge Token Exposure
ACP stores forge tokens in `runtime.env` files. These files:
- Are stored in `~/.agent-runtime/control-plane/profiles/<id>/`
- Should have restrictive file permissions (600)
- Should never be committed to version control

**Mitigation**: Run `chmod 600 runtime.env` and add to `.gitignore`.

### Dashboard Exposure
The ACP dashboard binds to `127.0.0.1` by default (local-only). If you change this:
- Use authentication (reverse proxy with OAuth)
- Use TLS/HTTPS
- Bind to specific interfaces only
- Use firewall rules to restrict access

## Dependency Management

ACP uses npm for dependency management. We:
- Run `npm audit` in CI
- Review dependency updates carefully
- Pin dependency versions where possible
- Monitor for security advisories

### Reporting Dependency Vulnerabilities

If you discover a vulnerable dependency:
1. Check if it's a direct or transitive dependency
2. Report via the process above
3. Or open a regular issue if it's a low-severity vulnerability

## Contact

For security-related questions:
- **Email**: security@agent-control-plane.dev
- **GitHub**: [@ducminhnguyen0319](https://github.com/ducminhnguyen0319)

---

*This security policy is based on [GitHub's security best practices](https://docs.github.com/en/code-security/getting-started/github-security-features).*
