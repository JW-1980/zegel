# Security Policy

## About This Project

Zegel is a cryptographic tamper-proof container format. Security is the entire purpose of this project. Files sealed in Zegel format must become physically unreadable if modified. Any vulnerability that undermines this guarantee is critical.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.2.x   | Yes       |
| < 1.2   | No        |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Email: **security@zegel.dev**

### What to Include

- Description of the vulnerability
- Affected component (format spec, lib/, cli/, app/)
- Steps to reproduce or proof of concept
- Potential impact (key recovery, plaintext leakage, integrity bypass)
- Suggested fix (optional)
- Your name/handle for credit (optional)

### What Constitutes a Vulnerability

In the context of Zegel, the following are security vulnerabilities:

- **Integrity bypass**: Modifying a .zgl file such that it still verifies as valid
- **Key recovery**: Recovering encryption key or derived keys without authorization
- **Plaintext leakage**: Extracting content without the correct key
- **Canary identification failure**: Determining which canary variant belongs to a recipient
- **Weak randomness**: Non-cryptographic RNG in security-critical paths
- **Nonce/IV reuse**: Initialization vector reuse across encryptions
- **Side-channel attacks**: Timing leaks in hash/HMAC comparisons
- **Redaction bypass**: Recovering content from redacted blocks
- **Selective disclosure bypass**: Accessing blocks not covered by a token
- **Shamir threshold bypass**: Reconstructing a key with fewer shares than the threshold
- **Key commitment failure**: File decrypting to different content with different keys
- **Audit trail tampering**: Modifying audit entries without detection
- **Expiration bypass**: Accessing content from an expired file

### Not Considered Vulnerabilities

- Denial of service through malformed files
- Issues requiring physical machine access
- Social engineering
- Dependency vulnerabilities (report to upstream, but notify us)

## Response Timeline

| Stage | Target |
|-------|--------|
| Acknowledgment | 48 hours |
| Initial assessment | 5 business days |
| Status update | 10 business days |
| Fix (critical) | 7 days |
| Fix (high) | 14 days |
| Fix (medium) | 30 days |
| Fix (low) | Next release |

## Disclosure Policy

We follow coordinated disclosure:

1. Reporter sends vulnerability to **security@zegel.dev**
2. We acknowledge within 48 hours
3. We investigate and assess severity
4. We develop and test a fix
5. We coordinate disclosure timeline with the reporter
6. We release the fix and publish a security advisory
7. Reporter may publish after fix is released

Credit is given unless anonymity is requested.

## Scope

This policy covers:
- Format specification (FORMAT_SPEC.md)
- Core Dart library (lib/)
- CLI application (cli/)
- Flutter GUI application (app/)
- Test vector generation (test_vectors/)
- Build and release infrastructure

## Security Best Practices for Users

- Verify .zgl files before trusting their contents
- Store encryption keys securely; never commit keys to version control
- Use strong passwords with password-derived encryption
- Distribute split-key shares through independent secure channels
- Keep Zegel up to date
- Verify binary integrity using published SHA-256 checksums
