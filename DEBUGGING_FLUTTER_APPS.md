# Debugging Flutter/Dart Apps on Headless Linux Systems

A practical guide for AI agents and developers working on Flutter applications
in CI/CD pipelines, containers, or headless environments.

---

## Table of Contents

1. [Environment Setup](#1-environment-setup)
2. [Installing Dart SDK](#2-installing-dart-sdk)
3. [Installing Flutter SDK](#3-installing-flutter-sdk)
4. [System Dependencies for Linux Builds](#4-system-dependencies-for-linux-builds)
5. [Static Analysis Workflow](#5-static-analysis-workflow)
6. [Common Issue Categories and Fixes](#6-common-issue-categories-and-fixes)
7. [Building the App](#7-building-the-app)
8. [Running Tests](#8-running-tests)
9. [Automated Fix Patterns](#9-automated-fix-patterns)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Environment Setup

### Prerequisites

- Linux x86_64 (tested on Ubuntu 24.04 LTS)
- `curl` or `wget` for downloading SDKs
- `unzip` for extracting the Dart SDK
- `tar` with xz support for extracting the Flutter SDK
- `git` for version control
- ~2.5 GB free disk space (Dart SDK ~200 MB + Flutter SDK ~750 MB compressed)

### Verify Your System

```bash
uname -m          # should show x86_64
cat /etc/os-release | head -3
which curl unzip tar git
```

---

## 2. Installing Dart SDK

The Dart SDK is needed for library-only packages that don't depend on Flutter.

```bash
# Download latest stable Dart SDK
curl -fsSL https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip \
  -o /tmp/dartsdk.zip

# Extract to /usr/local/lib
unzip -q /tmp/dartsdk.zip -d /usr/local/lib

# Add to PATH
export PATH="/usr/local/lib/dart-sdk/bin:$PATH"

# Verify
dart --version
```

### For ARM64 systems

Replace `x64` with `arm64` in the download URL:
```bash
curl -fsSL https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-arm64-release.zip \
  -o /tmp/dartsdk.zip
```

---

## 3. Installing Flutter SDK

The Flutter SDK includes Dart and is needed for Flutter app projects.

```bash
# Download Flutter SDK (stable channel)
curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.29.2-stable.tar.xz \
  -o /tmp/flutter.tar.xz

# Extract (takes a few minutes)
tar xf /tmp/flutter.tar.xz -C /usr/local/lib

# Fix git ownership (required in containers)
git config --global --add safe.directory /usr/local/lib/flutter

# Add to PATH (Flutter's bundled Dart takes priority)
export PATH="/usr/local/lib/flutter/bin:/usr/local/lib/flutter/bin/cache/dart-sdk/bin:$PATH"

# Verify
flutter --version
```

### Important Notes

- Flutter includes its own Dart SDK in `flutter/bin/cache/dart-sdk/`
- If you have both standalone Dart and Flutter installed, put Flutter's path
  first so `dart` resolves to Flutter's bundled version for consistency
- The `git config --global --add safe.directory` step is critical in Docker/CI
  environments where the SDK is extracted by a different user

---

## 4. System Dependencies for Linux Builds

Flutter Linux desktop builds require native GTK3 and related libraries.

```bash
# Core build tools
apt-get install -y \
  cmake \
  ninja-build \
  clang \
  pkg-config

# GTK3 development libraries (Flutter Linux desktop)
apt-get install -y libgtk-3-dev

# libsecret (required by flutter_secure_storage)
apt-get install -y libsecret-1-dev

# Optional: if the app uses jsoncpp
apt-get install -y libjsoncpp-dev
```

### Which packages are needed?

The exact set depends on the app's plugin dependencies. Common ones:

| Plugin                     | System Package         |
|----------------------------|------------------------|
| flutter (Linux desktop)    | `libgtk-3-dev`         |
| flutter_secure_storage     | `libsecret-1-dev`      |
| url_launcher_linux         | (included in GTK3)     |
| file_picker                | (Dart-only on Linux)   |

If a build fails with `pkg_check_modules` errors, the error message will
tell you which `.pc` package is missing. Install the corresponding `-dev`
package.

---

## 5. Static Analysis Workflow

This is the core debugging loop. Run it iteratively until clean.

### Step 1: Install Dependencies

```bash
cd /path/to/flutter/app
flutter pub get
```

### Step 2: Run Static Analysis

```bash
flutter analyze
```

For Dart-only packages (no Flutter dependency):
```bash
dart analyze
```

### Step 3: Interpret Results

The analyzer reports three severity levels:

| Severity  | Impact | Action |
|-----------|--------|--------|
| **error** | Won't compile | Must fix immediately |
| **warning** | Compiles but likely bug | Should fix |
| **info** | Code quality/style | Fix for clean builds |

### Step 4: Fix and Re-analyze

After fixes, re-run `flutter analyze`. Repeat until:
```
Analyzing app...
No issues found!
```

### Step 5: Build to Confirm

```bash
flutter build linux --release
```

### Step 6: Run Tests

```bash
# Flutter app tests
flutter test

# Dart library tests
cd /path/to/lib && dart test
```

---

## 6. Common Issue Categories and Fixes

### 6.1 ERRORS (Won't Compile)

#### Undefined identifier (missing import)

```
error - Undefined name 'Uint8List' - undefined_identifier
```

**Fix:** Add the missing import at the top of the file:
```dart
import 'dart:typed_data';  // for Uint8List, ByteData, etc.
```

Common missing imports:
- `dart:typed_data` -- `Uint8List`, `ByteData`, `Float64List`
- `dart:convert` -- `utf8`, `json`, `jsonEncode`, `jsonDecode`
- `dart:io` -- `File`, `Platform`, `Directory`
- `dart:async` -- `Completer`, `StreamController`

### 6.2 WARNINGS

#### Unused imports

```
warning - Unused import: 'dart:io' - unused_import
```

**Fix:** Remove the import line entirely.

#### Unused fields

```
warning - The value of the field '_inspection' isn't used - unused_field
```

**Fix:** Remove the field declaration and any assignments to it. Search for
all references: `_inspection =` and `_inspection.` to ensure nothing breaks.

#### Unused local variables

```
warning - The value of the local variable 'content' isn't used - unused_local_variable
```

**Fix options:**
- If the value is truly unused, remove the line
- If the call has side effects, keep the call but remove the assignment:
  `await file.readAsBytes();` instead of `final content = await file.readAsBytes();`
- If it's a placeholder for future implementation, prefix with underscore:
  `final _ = await file.readAsBytes();`

### 6.3 INFO (Code Quality)

#### Deprecated API: withOpacity

```
info - 'withOpacity' is deprecated. Use .withValues() - deprecated_member_use
```

**Fix:** Replace `.withOpacity(X)` with `.withValues(alpha: X)`:
```dart
// Before (deprecated in Flutter 3.27+)
color.withOpacity(0.5)

// After
color.withValues(alpha: 0.5)
```

This is typically the single most common issue in Flutter apps upgraded to
3.27+. A project may have 50-100+ instances.

#### prefer_const_constructors

```
info - Use 'const' with the constructor - prefer_const_constructors
```

**Fix:** Add `const` before the constructor call:
```dart
// Before
SizedBox(height: 16)

// After
const SizedBox(height: 16)
```

#### unnecessary_lambdas (closure should be a tearoff)

```
info - Closure should be a tearoff - unnecessary_lambdas
```

**Fix:** Replace the closure with a method reference:
```dart
// Before
onPressed: () => _handlePress()
items.map((e) => e.toString())

// After
onPressed: _handlePress
items.map((e) => e.toString())  // keep if lambda has different arity
```

Only apply when the closure simply delegates to a method with the same
argument signature. If the closure transforms arguments or captures
variables, keep it as-is.

#### use_build_context_synchronously

```
info - Don't use BuildContext across async gaps - use_build_context_synchronously
```

**Fix:** Add a `mounted` check before using `context` after an `await`:
```dart
// Before
await someAsyncOperation();
ScaffoldMessenger.of(context).showSnackBar(...);

// After
await someAsyncOperation();
if (!mounted) return;
ScaffoldMessenger.of(context).showSnackBar(...);
```

In StatelessWidget or non-State classes, use a captured `BuildContext`:
```dart
if (!context.mounted) return;
```

#### prefer_final_fields

```
info - The private field could be 'final' - prefer_final_fields
```

**Fix:** Add `final` to the field declaration if it's never reassigned:
```dart
// Before
List<int> _indices = [];

// After
final List<int> _indices = [];
```

---

## 7. Building the App

### Linux Desktop Build

```bash
# Enable Linux desktop (one-time)
flutter config --enable-linux-desktop

# Generate platform files if missing
flutter create --platforms=linux .

# Build release
flutter build linux --release

# Output location
ls build/linux/x64/release/bundle/
```

### Web Build (no native dependencies needed)

```bash
flutter build web --release
# Output: build/web/
```

### APK Build (requires Android SDK)

```bash
flutter build apk --release
```

---

## 8. Running Tests

### Dart Library Tests

```bash
cd lib/
dart pub get
dart test
```

### Flutter App Tests

```bash
cd app/
flutter pub get
flutter test
```

### Running a Specific Test File

```bash
dart test test/writer_test.dart
flutter test test/widget_test.dart
```

### With Verbose Output

```bash
dart test --reporter=expanded
flutter test --reporter=expanded
```

---

## 9. Automated Fix Patterns

### Batch withOpacity Replacement

The most efficient approach for the `withOpacity` → `withValues` migration
is to use the Edit tool with `replace_all: true` on each file:

```
Old: .withOpacity(0.1)
New: .withValues(alpha: 0.1)
```

Repeat for each opacity value used (0.1, 0.2, 0.3, 0.5, 0.7, etc.).

### Priority Order for Fixes

1. **Errors first** -- the app won't compile without these
2. **Warnings second** -- these indicate real bugs or dead code
3. **Info last** -- style/deprecation issues that affect code quality

### Agent Parallelization Strategy

When fixing a large number of files, split the work by directory:
- Agent 1: Fix all `lib/screens/` files
- Agent 2: Fix all `lib/widgets/` files
- Agent 3: Fix all `lib/services/` files

This avoids file conflicts since each agent works on different files.

---

## 10. Troubleshooting

### "dart: command not found"

The SDK is not on your PATH. Add it:
```bash
export PATH="/usr/local/lib/dart-sdk/bin:$PATH"
# or for Flutter:
export PATH="/usr/local/lib/flutter/bin:$PATH"
```

### "fatal: detected dubious ownership in repository"

Common in Docker containers. Fix:
```bash
git config --global --add safe.directory /usr/local/lib/flutter
```

### "No Linux desktop project configured"

The app's `linux/` directory is missing. Generate it:
```bash
flutter config --enable-linux-desktop
flutter create --platforms=linux .
```

### "pkg_check_modules: required packages not found"

Install the missing system library. The error message names the package:
```
The following required packages were not found:
 - gtk+-3.0        →  apt-get install libgtk-3-dev
 - libsecret-1     →  apt-get install libsecret-1-dev
```

### "Synthetic package output (package:flutter_gen) is deprecated"

This is a Flutter tooling warning, not an app issue. It can be suppressed
by adding to `l10n.yaml`:
```yaml
synthetic-package: false
```

### flutter_secure_storage build fails

Ensure libsecret is installed:
```bash
apt-get install -y libsecret-1-dev
```

### file_picker warnings about default_package

These are upstream plugin warnings. They don't affect builds or analysis.
The file_picker package needs updating by its maintainers.

---

## Quick Reference: Full Setup Script

```bash
#!/bin/bash
# Complete setup for Flutter debugging on headless Ubuntu 24.04

# 1. Install system dependencies
apt-get update && apt-get install -y \
  curl unzip tar git \
  cmake ninja-build clang pkg-config \
  libgtk-3-dev libsecret-1-dev

# 2. Install Dart SDK
curl -fsSL https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip \
  -o /tmp/dartsdk.zip
unzip -q /tmp/dartsdk.zip -d /usr/local/lib

# 3. Install Flutter SDK
curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.29.2-stable.tar.xz \
  -o /tmp/flutter.tar.xz
tar xf /tmp/flutter.tar.xz -C /usr/local/lib
git config --global --add safe.directory /usr/local/lib/flutter

# 4. Set PATH
export PATH="/usr/local/lib/flutter/bin:/usr/local/lib/flutter/bin/cache/dart-sdk/bin:/usr/local/lib/dart-sdk/bin:$PATH"

# 5. Enable Linux desktop
flutter config --enable-linux-desktop

# 6. Verify
dart --version
flutter --version
flutter doctor
```

---

## Appendix: Issue Counts from Zegel App Debugging Session

| Category | Count | Example |
|----------|-------|---------|
| error (undefined_identifier) | 1 | Missing `dart:typed_data` import |
| warning (unused_field) | 4 | `_inspection`, `_tokenFilePath`, `_classificationAuthority`, `_tsaUrl` |
| warning (unused_local_variable) | 4 | `fileService`, `success`, `content`, `filename` |
| warning (unused_import) | 1 | `dart:io` |
| info (deprecated_member_use) | 87 | `.withOpacity()` → `.withValues(alpha:)` |
| info (prefer_const_constructors) | 10 | Missing `const` on constructors |
| info (unnecessary_lambdas) | 7 | Closures that should be tearoffs |
| info (use_build_context_synchronously) | 4 | Missing `mounted` guards |
| info (prefer_final_fields) | 1 | Field should be `final` |
| **Total** | **131** | **All resolved to 0** |

Files modified: 24 (15 screens, 8 widgets, 1 service)

Result: `flutter analyze` → "No issues found!", `flutter build linux` → success.
