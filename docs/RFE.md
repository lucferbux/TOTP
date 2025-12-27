# TOTP App - Feature Roadmap & RFE (Request for Enhancement)

This document tracks planned features, enhancements, and future improvements for the TOTP Authenticator app.

---

## ✅ Implemented Features

### Core Functionality
- [x] **TOTP Code Generation** - RFC 6238 compliant time-based OTP
- [x] **HOTP Code Generation** - RFC 4226 compliant HMAC-based OTP
- [x] **Base32 Key Encoding/Decoding** - Automatic Base32 encoding from plain text input
- [x] **Plain Text Key Input** - Users paste plain text keys, app encodes automatically
- [x] **Configurable Intervals** - 30-second default, customizable
- [x] **Configurable Digits** - 6-10 digit codes supported

### Security
- [x] **Encrypted Storage** - ChaChaPoly encryption for OTP keys
- [x] **Keychain Integration** - Secure encryption key storage
- [x] **App Sandbox** - macOS sandbox compliance
- [x] **Secure Enclave Ready** - Architecture supports SE integration

### Data Management
- [x] **Local Storage** - UserDefaults with encryption
- [x] **App Groups** - Widget data sharing
- [x] **CloudKit Sync** - iCloud backup and sync
- [x] **CRUD Operations** - Add, edit, delete accounts

### User Interface
- [x] **Cross-Platform Design** - iOS and macOS support
- [x] **Responsive Layout** - Adaptive grid (1 col iPhone, 3 col iPad)
- [x] **Material Design** - Native iOS materials and blur effects
- [x] **Dark Mode** - Full dark theme support
- [x] **Circular Progress** - Visual countdown timer
- [x] **Pull to Refresh** - Reload accounts gesture
- [x] **Swipe Actions** - Swipe-to-reveal edit/delete
- [x] **Context Menu** - Long press for actions
- [x] **Floating Action Button** - Quick add on iOS
- [x] **Haptic Feedback** - Tactile response on copy
- [x] **Copy Toast** - Visual confirmation on copy

### Widget
- [x] **Home Screen Widget** - Quick TOTP access
- [x] **Multiple Sizes** - Small, medium, large widgets
- [x] **Account Selection** - Choose which account to display
- [x] **Timeline Updates** - 30-second refresh cycle

---

## 🚧 In Progress

### QR Code Scanning
- [ ] Camera integration for QR scanning
- [ ] Parse `otpauth://` URLs automatically
- [ ] Support Google Authenticator format
- [ ] Support Microsoft Authenticator format

---

## 📋 Planned Features

### P0 - Critical (Next Release)

#### Import/Export
- [ ] **Export Accounts** - Encrypted backup file
- [ ] **Import Accounts** - Restore from backup
- [ ] **Google Authenticator Migration** - Import from GA
- [ ] **iCloud Keychain Integration** - Optional sync method

#### Security Enhancements
- [ ] **Biometric Lock** - Face ID / Touch ID app lock
- [ ] **App Lock Timeout** - Configurable lock delay
- [ ] **Clipboard Auto-Clear** - Clear code after 30 seconds
- [ ] **Screenshot Prevention** - Secure view content

### P1 - High Priority

#### Account Management
- [ ] **Account Reordering** - Drag to reorder accounts
- [ ] **Account Groups/Folders** - Organize by category
- [ ] **Account Search** - Search by issuer or name
- [ ] **Account Icons** - Custom or auto-fetched icons
- [ ] **Duplicate Detection** - Warn on duplicate accounts

#### Sync & Backup
- [ ] **End-to-End Encryption** - Zero-knowledge sync
- [ ] **Multi-Device Sync** - Real-time updates
- [ ] **Offline Mode** - Full functionality without network
- [ ] **Backup Reminders** - Periodic backup prompts

#### Widget Improvements
- [ ] **Multi-Account Widget** - Show multiple codes
- [ ] **Lock Screen Widget** - iOS 16+ lock screen support
- [ ] **Watch App** - Apple Watch companion
- [ ] **Widget Tap to Copy** - Direct copy without app launch

### P2 - Medium Priority

#### UX Enhancements
- [ ] **Onboarding Flow** - First-launch tutorial
- [ ] **Accessibility** - VoiceOver optimization
- [ ] **Larger Text** - Dynamic type support
- [ ] **Reduce Motion** - Respect accessibility settings
- [ ] **Keyboard Shortcuts** - macOS keyboard navigation
- [ ] **Menu Bar App** - macOS menu bar quick access

#### Account Features
- [ ] **Custom Prefix** - Add prefix to copied code
- [ ] **Notes Field** - Add notes to accounts
- [ ] **Account Color** - Custom color per account
- [ ] **Last Used Timestamp** - Track usage frequency

#### Advanced OTP
- [ ] **Steam Guard** - Steam mobile authenticator format
- [ ] **Custom Algorithms** - SHA-256, SHA-512 support
- [ ] **Variable Time Offset** - Handle clock drift
- [ ] **HOTP Counter Sync** - Manual counter adjustment

### P3 - Low Priority (Future)

#### Platform Expansion
- [ ] **macOS Menu Bar App** - Standalone menu bar utility
- [ ] **Safari Extension** - Auto-fill OTP codes
- [ ] **Shortcuts Integration** - Siri Shortcuts support
- [ ] **CarPlay Support** - Emergency access (read-only)

#### Enterprise Features
- [ ] **MDM Support** - Mobile device management
- [ ] **Policy Enforcement** - Require biometric
- [ ] **Audit Logging** - Track code access
- [ ] **Admin Console** - Fleet management

#### Community
- [ ] **Open Source Components** - OSS the OTP library
- [ ] **Localization** - Multi-language support
- [ ] **Themes** - Custom color themes
- [ ] **Icon Packs** - Third-party icon packs

---

## 🐛 Known Issues

### Current
1. Widget may show stale data if app hasn't been launched recently
2. CloudKit sync may fail silently on network errors
3. HOTP counter not synced between devices

### Resolved (Last 3 Releases)
- ~~Swipe gesture conflict with ScrollView~~ (Fixed)
- ~~Dark mode contrast issues~~ (Fixed)
- ~~Widget timeline not updating~~ (Fixed)

---

## 💡 Feature Requests

### Community Requested
| Feature | Votes | Status |
|---------|-------|--------|
| QR Code Scanning | ⭐⭐⭐⭐⭐ | In Progress |
| Biometric Lock | ⭐⭐⭐⭐ | Planned P0 |
| Apple Watch App | ⭐⭐⭐ | Planned P1 |
| Import from Authy | ⭐⭐ | Backlog |
| Desktop Widget | ⭐⭐ | Backlog |

### Submitting Requests
To request a new feature:
1. Check if it's already listed above
2. Open a GitHub Issue with `[RFE]` prefix
3. Describe the use case and expected behavior
4. Vote on existing requests with 👍

---

## 📊 Technical Debt

### Code Quality
- [ ] Increase test coverage to 80%
- [ ] Add UI automation tests
- [ ] Document all public APIs
- [ ] Refactor SharedDataManager for testability
- [ ] Extract encryption logic to separate module

### Performance
- [ ] Profile and optimize widget timeline generation
- [ ] Lazy load account icons
- [ ] Cache decrypted keys in memory (with timeout)

### Architecture
- [ ] Consider TCA (The Composable Architecture)
- [ ] Evaluate Swift Data migration
- [ ] Abstract storage layer for testing
- [ ] Implement proper DI container

---

## 📅 Release Schedule

| Version | Target Date | Focus |
|---------|-------------|-------|
| 1.1 | Q1 2025 | QR Scanning, Biometric Lock |
| 1.2 | Q2 2025 | Import/Export, Watch App |
| 1.3 | Q3 2025 | Folders, Advanced Sync |
| 2.0 | Q4 2025 | Major UI Refresh |

---

## Contributing

When implementing features from this list:
1. Reference the RFE ID in your commit message
2. Update this file to move item to "In Progress"
3. Add tests for new functionality
4. Update documentation
5. Mark as "Implemented" when merged

---

*Last Updated: December 2024*
