# TOTP Authenticator - Technical Documentation

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [OTP Implementation](#otp-implementation)
4. [Security Model](#security-model)
5. [Data Persistence](#data-persistence)
6. [Widget Integration](#widget-integration)
7. [Cross-Platform Support](#cross-platform-support)
8. [API Reference](#api-reference)

---

## Overview

The TOTP Authenticator is a native iOS/macOS application that generates time-based one-time passwords (TOTP) and HMAC-based one-time passwords (HOTP) for two-factor authentication.

### Key Principles

1. **Security First**: All sensitive data is encrypted at rest
2. **Cross-Platform**: Single codebase for iOS and macOS
3. **No Dependencies**: Uses only Apple frameworks
4. **Standards Compliant**: RFC 4226 (HOTP) and RFC 6238 (TOTP)

---

## Architecture

### Layer Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Presentation Layer                       │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐ │
│  │ ContentView  │ │  TotpView    │ │  AddingPageView      │ │
│  └──────────────┘ └──────────────┘ └──────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                      Business Logic                          │
│  ┌──────────────────────┐ ┌────────────────────────────────┐│
│  │  SharedDataManager   │ │  CloudKitDataManager           ││
│  │  (ObservableObject)  │ │  (ObservableObject)            ││
│  └──────────────────────┘ └────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│                       Data Layer                             │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐ │
│  │  OtpModel    │ │  OtpEntry    │ │ CloudKitOtpModel     │ │
│  └──────────────┘ └──────────────┘ └──────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                       Core Layer                             │
│  ┌──────────────────────┐ ┌────────────────────────────────┐│
│  │  HOTP (hotpCode)     │ │  Encryption (ChaChaPoly)       ││
│  └──────────────────────┘ └────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

```
User Action → View → DataManager → Storage
                 ↓
            State Update → View Refresh
```

---

## OTP Implementation

### HOTP Algorithm (RFC 4226)

The HOTP algorithm generates a one-time password from a shared secret key and a counter.

```swift
public func hotpCode(key: Data, digits: Int = 6, counter: UInt64) -> UInt64 {
    // 1. Convert counter to 8-byte big-endian array
    let counterBytes = (0..<8).reversed().map { UInt8(counter >> (8 * $0) & 0xff) }
    
    // 2. Compute HMAC-SHA1
    let hash = HMAC<Insecure.SHA1>.authenticationCode(
        for: counterBytes, 
        using: SymmetricKey(data: key)
    )
    
    // 3. Dynamic truncation
    let offset = Int(hash.suffix(1)[0] & 0x0f)
    let hash32 = hash.dropFirst(offset).prefix(4)
        .reduce(0, { ($0 << 8) | UInt32($1) })
    let hash31 = hash32 & 0x7FFF_FFFF
    
    // 4. Compute OTP value
    return UInt64(String((pad + String(hash31)).suffix(digits)))!
}
```

### TOTP Algorithm (RFC 6238)

TOTP extends HOTP by using time as the counter:

```swift
case let .totp(key, digits, interval):
    let counter = UInt64(Date().timeIntervalSince1970 / interval)
    return hotpCode(key: key, digits: digits, counter: counter)
```

### OtpEntry Enum

```swift
public enum OtpEntry: Hashable {
    case hotp(key: Data, digits: Int, counter: UInt64)
    case totp(key: Data, digits: Int, interval: Double)
    
    public mutating func code() -> UInt64
    public func get_display_value() -> Int
}
```

---

## Security Model

### Encryption Flow

```
┌─────────────┐     ┌─────────────────┐     ┌────────────────┐
│  OTP Key    │ ──→ │  ChaChaPoly     │ ──→ │  UserDefaults  │
│  (plaintext)│     │  Encryption     │     │  (encrypted)   │
└─────────────┘     └─────────────────┘     └────────────────┘
                           ↑
                    ┌──────┴──────┐
                    │  SymmetricKey │
                    │  (Keychain)   │
                    └─────────────┘
```

### Key Management

```swift
private static func getOrCreateEncryptionKey() -> SymmetricKey {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "TOTP-SharedData-Encryption",
        kSecAttrAccessGroup as String: "group.com.lucferbux.TOTP",
        kSecReturnData as String: true
    ]
    
    // Try to load existing key
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    
    if status == errSecSuccess, let keyData = result as? Data {
        return SymmetricKey(data: keyData)
    }
    
    // Generate new 256-bit key
    let newKey = SymmetricKey(size: .bits256)
    // Store in Keychain...
    return newKey
}
```

### Encryption/Decryption

```swift
public func encryptData(_ data: Data) throws -> Data {
    return try ChaChaPoly.seal(data, using: encryptionKey).combined
}

public func decryptData(_ encryptedData: Data) throws -> Data {
    let sealedBox = try ChaChaPoly.SealedBox(combined: encryptedData)
    return try ChaChaPoly.open(sealedBox, using: encryptionKey)
}
```

---

## Data Persistence

### Storage Architecture

| Storage | Purpose | Encryption |
|---------|---------|------------|
| UserDefaults (App Group) | Account data | Yes (ChaChaPoly) |
| Keychain | Encryption key | Yes (Hardware) |
| CloudKit | Sync backup | Yes (ChaChaPoly) |

### StoredOtpAccount Model

```swift
private struct StoredOtpAccount: Codable {
    let id: String
    let issuer: String?
    let name: String?
    let prefix: String?
    let encryptedKey: Data  // ChaChaPoly encrypted
    let isHotp: Bool
    let digits: Int
    let interval: Double
    let counter: Int64
    let createdDate: Date
    let modifiedDate: Date
}
```

### CRUD Operations

```swift
// Create
func addAccount(_ account: OtpModel)

// Read
func loadAccounts()

// Update
func saveAccounts()

// Delete
func deleteAccount(_ account: OtpModel)
func deleteAccount(withId id: UUID)
```

---

## Widget Integration

### Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Main App      │ ──→ │   App Groups    │ ←── │    Widget       │
│   (write)       │     │   UserDefaults  │     │    (read)       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               ↓
                        ┌─────────────────┐
                        │    Keychain     │
                        │  (shared key)   │
                        └─────────────────┘
```

### Timeline Provider

```swift
struct Provider: AppIntentTimelineProvider {
    func timeline(for configuration: ConfigurationAppIntent, 
                  in context: Context) async -> Timeline<TOTPEntry> {
        var entries: [TOTPEntry] = []
        
        // Generate entries for next 5 minutes (every 30 seconds)
        for secondOffset in stride(from: 0, to: 300, by: 30) {
            let entryDate = Calendar.current.date(
                byAdding: .second, 
                value: secondOffset, 
                to: Date()
            )!
            entries.append(TOTPEntry(date: entryDate, ...))
        }
        
        return Timeline(entries: entries, policy: .atEnd)
    }
}
```

### Widget Sizes

| Size | Accounts Shown |
|------|----------------|
| systemSmall | 1 |
| systemMedium | 2 |
| systemLarge | 4 |

---

## Cross-Platform Support

### Conditional Compilation

```swift
#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
import ServiceManagement
#endif
```

### Platform Abstractions

#### PlatformPasteboard
```swift
struct PlatformPasteboard {
    static func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
```

#### PlatformColors
```swift
struct PlatformColors {
    static var secondarySystemBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #else
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
}
```

### macOS-Specific Components

#### MacOSAppSettings (`Helper/MacOSAppSettings.swift`)
`ObservableObject` managing macOS-exclusive preferences:
- **Launch at Login** — Uses `SMAppService.mainApp` to register/unregister as a login item
- **Show Dock Icon** — Toggles `NSApp.setActivationPolicy(.accessory)` vs `.regular`
- **Window Management** — `showMainWindow()` to activate the main window from the menu bar

Preferences are persisted in `UserDefaults` with keys prefixed `macOS_`.

#### MenuBarView (`View/MenuBarView.swift`)
Menu bar popover rendered via `MenuBarExtra` with `.window` style:
- Lists all synced TOTP accounts with live countdown timers
- Clicking a row copies `(prefix ?? "") + code` to clipboard
- Search field for filtering accounts (shown when > 3 accounts)
- "Open Main Window" and "Quit" footer actions
- Auto-refreshes codes every second via `Timer.publish`

#### SettingsView (`View/SettingsView.swift`)
macOS Settings window accessible via ⌘, (standard `Settings` scene):
- General section: Launch at Login toggle, Show Dock Icon toggle
- Status section: Login item state, dock visibility indicator
- About section: Version and build information

#### MacAppDelegate (`TOTPApp.swift`)
macOS `NSApplicationDelegate` adaptor handling:
- Remote notification registration for CloudKit push sync
- Dock icon policy application on launch
- Window reopen behavior when clicking the Dock icon

### Platform-Specific UI

```swift
// iOS-only floating action button
#if os(iOS)
VStack {
    Spacer()
    HStack {
        Spacer()
        Button(action: addAccount) {
            Image(systemName: "plus")
        }
    }
}
#endif

// macOS hover effect on TOTP cards
#if os(macOS)
.onHover { hovering in
    withAnimation(.smooth(duration: 0.15)) {
        isHovered = hovering
    }
}
#endif
```

---

## API Reference

### OtpModel

```swift
public struct OtpModel: Identifiable, Hashable {
    public let id: UUID
    public var issuer: String?
    public var name: String?
    public var prefix: String?
    public var entry: OtpEntry
}
```

### OtpEntry

```swift
public enum OtpEntry: Hashable {
    case hotp(key: Data, digits: Int, counter: UInt64)
    case totp(key: Data, digits: Int, interval: Double)
    
    // Generate code (mutating for HOTP to increment counter)
    public mutating func code() -> UInt64
    
    // Get display value (seconds remaining for TOTP, counter for HOTP)
    public func get_display_value() -> Int
}
```

### SharedDataManager

```swift
public class SharedDataManager: ObservableObject {
    public static let shared: SharedDataManager
    
    @Published public var accounts: [OtpModel]
    @Published public var isLoading: Bool
    @Published public var error: SharedDataError?
    
    public func loadAccounts()
    public func saveAccounts()
    public func addAccount(_ account: OtpModel)
    public func deleteAccount(_ account: OtpModel)
    public func encryptData(_ data: Data) throws -> Data
    public func decryptData(_ encryptedData: Data) throws -> Data
}
```

### SharedDataError

```swift
public enum SharedDataError: LocalizedError, Identifiable {
    case loadFailed(Error)
    case saveFailed(Error)
    case encryptionFailed
    case decryptionFailed
    case unknown(Error)
}
```

---

## Testing

### Unit Tests

```swift
@Test func testHotpCodeGeneration() async throws {
    // RFC 4226 test vectors
    let key = "12345678901234567890".data(using: .ascii)!
    let expectedResults: [UInt64: UInt64] = [
        0: 755224,
        1: 287082,
        // ...
    ]
    
    for (counter, expected) in expectedResults {
        let result = hotpCode(key: key, digits: 6, counter: counter)
        #expect(result == expected)
    }
}
```

### Test Coverage Goals

- [ ] 80% code coverage
- [ ] All RFC test vectors passing
- [ ] Encryption/decryption round-trip tests
- [ ] UI automation tests

---

## Performance Considerations

1. **Lazy Loading**: Accounts are decrypted on demand
2. **Timer Efficiency**: Single 1-second timer shared across views
3. **Widget Timeline**: Pre-computed entries minimize runtime cost
4. **Memory**: Keys held in memory only when needed

---

*Last Updated: December 2024*
