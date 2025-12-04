# TOTP Authenticator

A secure, native TOTP (Time-based One-Time Password) authenticator app for iOS and macOS built entirely with SwiftUI and Apple frameworks.

<p align="center">
  <img src="docs/assets/app-icon.png" alt="TOTP App Icon" width="128">
</p>

## Features

### 🔐 Security First
- **RFC 4226 & RFC 6238 Compliant** - Standard HOTP and TOTP algorithms
- **ChaChaPoly Encryption** - All OTP keys encrypted at rest
- **Keychain Storage** - Encryption keys stored securely in iOS/macOS Keychain
- **App Sandbox** - Full macOS sandbox compliance
- **No Third-Party Dependencies** - 100% Apple frameworks

### 📱 Cross-Platform
- Native iOS app (iPhone & iPad)
- Native macOS app (Apple Silicon & Intel)
- Shared codebase with platform-specific optimizations
- Universal purchase across all platforms

### 🎨 Modern UI/UX
- Responsive layout (single column on iPhone, grid on iPad)
- Material design with blur effects
- Dark mode support
- Haptic feedback
- Swipe-to-reveal actions
- Context menu support
- Pull-to-refresh
- Floating action button

### ☁️ Sync & Backup
- iCloud sync via CloudKit
- App Groups for widget data sharing
- Encrypted backups

### ⚡ Widget Support
- Home screen widgets (small, medium, large)
- Real-time 30-second updates
- Account selection
- One-tap code access

## Screenshots

| iPhone | iPad | macOS |
|--------|------|-------|
| ![iPhone](docs/assets/screenshot-iphone.png) | ![iPad](docs/assets/screenshot-ipad.png) | ![macOS](docs/assets/screenshot-macos.png) |

## Installation

### Requirements
- iOS 18.2+ / macOS 14+
- Xcode 16+
- Swift 5.9+

### Build from Source

```bash
# Clone the repository
git clone https://github.com/lucferbux/TOTP.git
cd TOTP

# Open in Xcode
open TOTP.xcodeproj
```

### App Store
Coming soon to the App Store.

## Usage

### Adding an Account

1. Tap the **+** button (or use ⌘N on macOS)
2. Choose TOTP or HOTP mode
3. Enter your secret key (Base32 encoded)
4. Configure interval and digits if needed
5. Add issuer and account name
6. Tap **Add Account**

### Copying Codes

- **Tap** any account card to copy the code
- Code is copied to clipboard with haptic feedback
- A toast notification confirms the copy

### Managing Accounts

- **Swipe left** to reveal Edit and Delete buttons
- **Long press** to access context menu
- **Pull down** to refresh accounts

## Architecture

```
TOTP/
├── Generator/              # OTP code generation
│   ├── HOTP.swift         # HMAC-based OTP (RFC 4226)
│   └── OTP.swift          # OTP entry types
├── Model/                  # Data layer
│   ├── OtpModel.swift     # Core account model
│   ├── SharedDataManager.swift  # Local storage
│   └── CloudKitDataManager.swift  # iCloud sync
├── View/                   # UI layer
│   ├── ContentView.swift  # Main list view
│   ├── TotpView.swift     # Account card
│   └── AddingPageView.swift  # Add account form
├── Helper/                 # Utilities
│   ├── Data+Base32.swift  # Base32 decoding
│   └── PlatformUtilities.swift  # Cross-platform helpers
└── TOTPApp.swift          # App entry point
```

### Key Technologies

| Component | Technology |
|-----------|------------|
| UI | SwiftUI |
| Cryptography | CryptoKit (HMAC-SHA1, ChaChaPoly) |
| Storage | UserDefaults + Keychain |
| Sync | CloudKit |
| Widget | WidgetKit |
| Testing | Swift Testing |

## Security

### How Keys Are Protected

1. **Encryption**: All OTP secret keys are encrypted using ChaChaPoly before storage
2. **Key Management**: The master encryption key is stored in the iOS/macOS Keychain
3. **App Groups**: Widget access uses shared encrypted storage with the same key
4. **No Plaintext**: Keys are never stored or transmitted in plaintext

### Best Practices

- Enable device passcode/biometrics
- Keep your device updated
- Never share your secret keys
- Use the app's export feature for backups

## Development

### Running Tests

```bash
# Run all tests
xcodebuild test -scheme TOTP -destination 'platform=iOS Simulator,name=iPhone 16'

# Run specific test file
swift test --filter TOTPTests
```

### Code Style

This project follows the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) and uses SwiftLint (coming soon).

### Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for detailed guidelines.

## Roadmap

See [RFE.md](docs/RFE.md) for the full feature roadmap including:

- 🔜 QR Code scanning
- 🔜 Biometric app lock
- 🔜 Apple Watch app
- 🔜 Import/Export functionality

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [RFC 4226](https://tools.ietf.org/html/rfc4226) - HOTP Algorithm
- [RFC 6238](https://tools.ietf.org/html/rfc6238) - TOTP Algorithm
- Apple's CryptoKit team for excellent cryptographic APIs

## Support

- 📫 [Open an Issue](https://github.com/lucferbux/TOTP/issues)
- 💬 [Discussions](https://github.com/lucferbux/TOTP/discussions)

---

<p align="center">
  Made with ❤️ using SwiftUI
</p>
