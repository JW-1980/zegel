# Contributing to Zegel

Thank you for your interest in contributing to Zegel! This document provides guidelines for contributing.

## Code of Conduct

Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before contributing. By participating, you are expected to uphold this code.

## Security Vulnerabilities

**Do not open a public issue for security vulnerabilities.** Refer to [SECURITY.md](SECURITY.md) for responsible disclosure instructions.

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/<your-username>/zegel.git
   ```
3. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Environment

### Prerequisites

- **Dart SDK** >= 3.0.0 (for lib/ and cli/)
- **Flutter SDK** >= 3.10.0 (for app/)

### Setup

```bash
# Core library
cd lib && dart pub get

# CLI
cd ../cli && dart pub get

# Flutter app
cd ../app && flutter pub get
```

## Project Structure

```
zegel/
  lib/           # Core Dart library (format reader/writer, crypto, Merkle tree)
  cli/           # Command-line interface (thin wrapper around lib/)
  app/           # Flutter GUI application (Windows, macOS, Linux, Android, iOS)
  test_vectors/  # Language-agnostic test vectors
  docs/          # Documentation
```

**FORMAT_SPEC.md is the single source of truth.** All implementations must conform to the format specification. If you believe the spec has an error, propose a spec change first, then update code.

## Running Tests

```bash
# Core library tests
cd lib && dart test

# CLI tests
cd cli && dart test

# Flutter app tests
cd app && flutter test
```

## Code Style

### Formatting and Analysis

```bash
dart format .
dart analyze --fatal-infos
```

### Guidelines

- Follow [Effective Dart](https://dart.dev/effective-dart)
- Document all public APIs with `///` dartdoc comments
- Use `const` constructors where possible
- Never use `dart:math` `Random()` for cryptographic purposes
- Use constant-time comparison for all hash/HMAC checks

## Pull Request Process

1. Push your branch and open a PR against `main`
2. Fill in the PR template with a clear description
3. Ensure all CI checks pass

### PR Checklist

- [ ] Tests pass in lib/, cli/, and app/
- [ ] `dart format .` applied
- [ ] `dart analyze` reports zero issues
- [ ] New public APIs have dartdoc documentation
- [ ] CHANGELOG.md updated for user-facing changes
- [ ] No secrets, keys, or sensitive data in the diff
- [ ] Test vectors updated if format behavior changed

## Commit Message Conventions

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

### Types

| Type | Description |
|------|-------------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation changes |
| `style` | Code style changes (no logic change) |
| `refactor` | Code refactoring |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `build` | Build system or dependency changes |
| `ci` | CI/CD configuration changes |
| `security` | Security-related changes |

### Scopes

Use `lib`, `cli`, `app`, `spec`, or `vectors`.

### Examples

```
feat(lib): add Shamir's Secret Sharing key splitting
fix(cli): correct key file reading on Windows paths
docs(spec): clarify Merkle tree leaf ordering
test(lib): add tamper detection tests for every bit position
```

## Reporting Issues

### Bug Reports

Include: Zegel version, OS, Dart/Flutter SDK version, steps to reproduce, expected vs actual behavior.

### Feature Requests

Include: clear description, motivation/use case, and whether you're willing to implement it.

## License

By contributing, you agree that your contributions will be licensed under Apache License 2.0 (code) and CC BY 4.0 (specification/documentation).
