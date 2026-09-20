# Contributing to TOTP Password

Thank you for your interest in contributing to the TOTP Password! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Testing](#testing)
- [Documentation](#documentation)

---

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment. Be kind, constructive, and professional in all interactions.

---

## Getting Started

### Prerequisites

- macOS 27 or later
- Xcode 27 or later (iOS / macOS 27 SDKs)
- An Apple Developer account (for testing on devices)

### Fork and Clone

```bash
# Fork the repository on GitHub, then:
git clone https://github.com/YOUR_USERNAME/TOTP.git
cd TOTP
git remote add upstream https://github.com/lucferbux/TOTP.git
```

---

## Development Setup

### Opening the Project

```bash
open TOTP.xcodeproj
```

### Configuring Signing

1. Open the project in Xcode
2. Select the TOTP target
3. Go to "Signing & Capabilities"
4. Select your development team
5. Update the bundle identifier if needed

### App Groups & Keychain

For full functionality including widget support:

1. Create an App Group in your Apple Developer account
2. Update `group.com.lucferbux.TOTP` to your App Group identifier
3. Update Keychain access groups accordingly

### Running Tests

```bash
# Command line
xcodebuild test -scheme TOTP -destination 'platform=iOS Simulator,name=iPhone 16'

# Or use Xcode: ⌘+U
```

---

## Coding Standards

### Swift Style Guide

We follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).

#### Naming Conventions

```swift
// ✅ Good
struct OtpModel { }
class SharedDataManager { }
func calculateCode() -> UInt64

// ❌ Bad
struct otp_model { }
class data_manager { }
func calc() -> UInt64
```

#### File Organization

```swift
// 1. Imports
import SwiftUI
import CryptoKit

// 2. Type declaration
public struct MyView: View {
    // 3. Properties (in order)
    //    - Static/class properties
    //    - Instance properties
    //    - @State/@Binding
    
    // 4. Initializers
    
    // 5. Body (for Views)
    
    // 6. Methods
}

// 7. Extensions
extension MyView {
    // Helper methods
}
```

#### SwiftUI Best Practices

```swift
// ✅ Use appropriate property wrappers
@State private var localState: Bool = false
@StateObject private var manager = DataManager.shared
@Binding var externalState: Bool

// ✅ Extract complex views
var body: some View {
    VStack {
        headerView
        contentView
        footerView
    }
}

private var headerView: some View {
    // Complex header implementation
}
```

### Cross-Platform Code

Always consider both iOS and macOS:

```swift
// ✅ Use conditional compilation
#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

// ✅ Use platform abstractions
PlatformPasteboard.copyToClipboard(text)

// ❌ Don't use platform-specific types directly
UIPasteboard.general.string = text  // iOS only!
```

### Security Requirements

```swift
// ✅ Always encrypt sensitive data
let encrypted = try ChaChaPoly.seal(data, using: key).combined

// ✅ Use Keychain for keys
let query = [kSecClass: kSecClassGenericPassword, ...]

// ❌ Never store plaintext secrets
UserDefaults.standard.set(secretKey, forKey: "key")

// ❌ Never log sensitive data
print("Secret key: \(secretKey)")  // NEVER!
```

---

## Commit Guidelines

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no code change |
| `refactor` | Code change, no new feature or fix |
| `test` | Adding tests |
| `chore` | Build, CI, or tooling changes |

### Examples

```bash
feat(widget): add multi-account support for large widget

fix(otp): correct HOTP counter increment logic

docs(readme): add installation instructions

refactor(storage): extract encryption into separate module

test(hotp): add RFC 4226 test vectors
```

### Scopes

- `app` - Main app
- `widget` - Widget extension
- `otp` - OTP generation
- `storage` - Data persistence
- `ui` - User interface
- `security` - Security/encryption

---

## Pull Request Process

### Before Submitting

1. **Update from upstream**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Run tests**
   ```bash
   xcodebuild test -scheme TOTP -destination 'platform=iOS Simulator,name=iPhone 16'
   ```

3. **Check for warnings**
   - Build should complete with zero warnings
   - Fix any SwiftLint issues (when enabled)

4. **Update documentation**
   - Update README if adding features
   - Add inline documentation for public APIs
   - Update RFE.md if implementing a planned feature

### PR Template

When creating a PR, include:

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests pass
- [ ] UI tests pass
- [ ] Tested on iOS
- [ ] Tested on macOS

## Screenshots (if applicable)

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No new warnings
```

### Review Process

1. At least one maintainer approval required
2. All CI checks must pass
3. No unresolved conversations
4. Squash commits before merge

---

## Testing

### Unit Tests

Located in `TOTPTests/`:

```swift
@Test func testFeature() async throws {
    // Arrange
    let input = ...
    
    // Act
    let result = function(input)
    
    // Assert
    #expect(result == expected)
}
```

### Test Requirements

- All new features must include tests
- Bug fixes should include regression tests
- Aim for 80% code coverage
- RFC compliance tests are required for OTP changes

### Running Tests

```bash
# All tests
xcodebuild test -scheme TOTP -destination 'platform=iOS Simulator,name=iPhone 16'

# Specific test
swift test --filter testHotpCodeGeneration
```

---

## Documentation

### Inline Documentation

```swift
/// Generates an HMAC-based One-Time Password.
///
/// Implements RFC 4226 HOTP algorithm.
///
/// - Parameters:
///   - key: The shared secret key (binary data)
///   - digits: Number of digits in output (default: 6)
///   - counter: The counter value
/// - Returns: The OTP as an unsigned 64-bit integer
public func hotpCode(key: Data, digits: Int = 6, counter: UInt64) -> UInt64 {
    // Implementation
}
```

### Documentation Files

- `README.md` - Project overview and quick start
- `docs/ARCHITECTURE.md` - Technical architecture
- `docs/RFE.md` - Feature roadmap
- `docs/CONTRIBUTING.md` - This file

---

## Questions?

- Open a [Discussion](https://github.com/lucferbux/TOTP/discussions)
- Check existing [Issues](https://github.com/lucferbux/TOTP/issues)

Thank you for contributing! 🎉
