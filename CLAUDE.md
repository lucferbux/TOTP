# CLAUDE.md

Guidance for Claude Code (and other AI agents) working in this repository. This is the single source of truth for working conventions in this project.

## Project Overview

**TOTP Authenticator** — a native, multi-platform SwiftUI authenticator that generates 2FA codes per **RFC 4226 (HOTP)** and **RFC 6238 (TOTP)**. Single codebase shipping to **iPhone, iPad, and Mac** (Universal Purchase), with **iCloud/CloudKit sync**, a **home-screen Widget**, an **AutoFill credential provider**, and a **macOS menu bar** mode. No third-party dependencies — 100% Apple frameworks.

- **Language / mode:** Swift (Swift 5 language mode — `SWIFT_VERSION = 5.0`)
- **UI:** SwiftUI with the **iOS 26 "Liquid Glass"** design language
- **Deployment targets:** iOS/iPadOS **26.0+**, macOS **26.0+** (visionOS is also a supported platform)
- **Toolchain:** Xcode **26.x** (this machine: Xcode 26.5)
- **Crypto:** CryptoKit — `HMAC<Insecure.SHA1>` for OTP, `ChaChaPoly` for at-rest encryption

> ⚠️ [README.md](README.md) and [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) still list older requirements (iOS 18.2 / macOS 14 / Xcode 16 / Swift 5.9). Those are **stale** — trust this file and the Xcode project settings instead.

## Build, Run & Test

The project file is `TOTP.xcodeproj` (no `.xcworkspace`, no SPM/Cocoapods).

| Target | Scheme | Bundle ID |
|--------|--------|-----------|
| Main app | `TOTP` | `com.lucferbux.TOTP` |
| Widget extension | `TOTP WidgetExtension` | `com.lucferbux.TOTP.TOTP-Widget` |
| AutoFill extension | `TOTP Autofill` | `com.lucferbux.TOTP.TOTP-Autofill` |
| Unit tests | (via `TOTP`) → `TOTPTests` | `com.lucferbux.TOTPTests` |
| UI tests | (via `TOTP`) → `TOTPUITests` | `com.lucferbux.TOTPUITests` |

```bash
# List schemes / targets
xcodebuild -list -project TOTP.xcodeproj

# Build for iOS Simulator
xcodebuild build -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Build for macOS
xcodebuild build -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=macOS'

# Run the full test suite (unit + UI) on iOS Simulator
xcodebuild test -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run only the unit tests
xcodebuild test -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:TOTPTests
```

- Pick a destination that actually exists: `xcrun simctl list devices available`. iPad-class verification: `name=iPad Pro 11-inch (M4)`.
- Prefer the project's **`build-run-totp`** and **`test-totp`** skills — they wrap these commands, pick a live simulator, and pipe through `xcbeautify` when available.
- CloudKit, AutoFill, App Groups, and Keychain sharing require a signing team and provisioned containers; they **do not work in unsigned simulator builds**. Don't treat sync/AutoFill failures in a bare simulator as regressions.

## Architecture

Layering (see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full reference):

```
View (SwiftUI)  →  SyncManager  →  SharedDataManager (local)   →  UserDefaults(App Group) + Keychain
                        │          CloudKitDataManager (cloud)  →  CloudKit (iCloud.com.lucferbux.TOTP)
                        └────────→  Core: HOTP/OTP + ChaChaPoly encryption
```

### Project structure

```
TOTP/
├── TOTPApp.swift          # @main entry; iOS scenes + macOS MenuBarExtra/Settings + MacAppDelegate
├── Generator/             # OTP math (pure, no platform deps)
│   ├── HOTP.swift         # hotpCode() — RFC 4226 HMAC-SHA1 + dynamic truncation
│   └── OTP.swift          # OtpEntry enum: .hotp / .totp; code(); get_display_value()
├── Model/                 # Data + persistence + sync
│   ├── OtpModel.swift             # Identifiable account model (id/issuer/name/prefix/entry)
│   ├── SharedDataManager.swift    # Encrypted local store (App Group UserDefaults). @Published accounts
│   ├── CloudKitDataManager.swift  # CloudKit CRUD + account status + push
│   ├── CloudKitOtpModel.swift     # CKRecord <-> model mapping
│   └── SyncManager.swift          # Orchestrates local⇄cloud (last-write-wins), AutoFill identities, widget reload
├── View/                  # SwiftUI views
│   ├── ContentView.swift          # Main list/grid
│   ├── TotpView.swift             # Single account card (copy, swipe, context menu)
│   ├── AddingPageView.swift       # Add/edit form
│   ├── SettingsView.swift         # macOS ⌘, settings window
│   └── MenuBarView.swift          # macOS menu bar popover
├── Helper/
│   ├── PlatformUtilities.swift    # PlatformPasteboard / PlatformColors cross-platform shims
│   ├── EncryptionKeyManager.swift # Keychain-backed SymmetricKey
│   ├── Data+Base32.swift          # Base32 encode/decode
│   └── MacOSAppSettings.swift     # Launch-at-login (SMAppService), Dock policy
TOTP Widget/               # WidgetKit extension (AppIntent timeline, CopyTOTPCodeIntent)
TOTP AutoFill/             # ASCredentialProvider extension (CredentialProviderViewController, OTPSelectionView)
TOTPTests/ , TOTPUITests/  # Swift Testing unit tests + XCUITest UI tests
docs/                      # ARCHITECTURE.md, CONTRIBUTING.md, RFE.md (roadmap)
```

### Identifiers (must stay in sync across targets & entitlements)

- **App Group:** `group.com.lucferbux.TOTP` — the only channel for app↔widget↔autofill data sharing
- **Keychain access group:** `$(AppIdentifierPrefix)com.lucferbux.TOTP` — shared encryption key lives here
- **iCloud container:** `iCloud.com.lucferbux.TOTP` (CloudKit + CloudDocuments)
- **Encryption-key Keychain service:** `TOTP-SharedData-Encryption`

If you add a target or change an identifier, update **every** `*.entitlements` file plus the `pbxproj` consistently.

## Coding Standards

### iOS 26 design language (REQUIRED)

```swift
// Gate every new view/type that touches iOS 26 APIs:
@available(iOS 26.0, macOS 26.0, *)
struct MyView: View { ... }

// Native card surface (Journal-app style) — NOT glass:
.padding()
.background {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))   // use PlatformColors on shared code
}
.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

// Liquid Glass ONLY on the floating action button (FAB), never on cards:
.glassEffect(.regular.interactive())

// Modern modifiers:
.foregroundStyle(.secondary)                    // never .foregroundColor
.animation(.smooth(duration: 0.3), value: x)    // never .spring()
.contentTransition(.numericText())              // for changing codes
.symbolEffect(.pulse.byLayer, options: .repeating)
.sensoryFeedback(.impact, trigger: value)
```

### Cross-platform first

```swift
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// Route platform differences through the existing shims — don't reach for UIKit/AppKit directly:
PlatformPasteboard.copyToClipboard(code)
PlatformColors.secondarySystemBackground
// iOS-only UI: #if os(iOS) ... ; macOS-only (hover, menu bar): #if os(macOS) ...
```

### Naming

- Views `*View`, models `*Model`, managers `*Manager`, extensions `Type+Feature.swift`.
- Types/properties in `lowerCamelCase`/`UpperCamelCase` per the Swift API Design Guidelines. (Note: some existing OTP APIs use `snake_case` like `get_display_value()` — match the surrounding file when editing, but prefer camelCase for new APIs.)

### State management

`@State` for view-local, `@StateObject` for owned observables (`SyncManager.shared`, `SharedDataManager.shared`), `@ObservedObject` for injected, `@Binding` for parent-owned.

## Security (non-negotiable)

- OTP secret keys are **always** `ChaChaPoly`-sealed before they touch any persistent store (UserDefaults, CloudKit). Plaintext keys live in memory only while generating a code.
- The symmetric key is generated once and stored in the **Keychain** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, shared via the access group). Never hard-code or derive keys from constants.
- **Never** log, `print`, or put OTP keys / generated codes into analytics, error messages, or screenshots.
- Never write a secret to `UserDefaults` unencrypted. The widget and AutoFill extension decrypt independently using the shared Keychain key.

## Subsystem notes

- **OTP math** (`Generator/`) is pure and platform-free — keep it that way so it stays unit-testable. HOTP mutates and increments its counter on each `code()`; TOTP derives the counter from `Date()`.
- **Sync** (`SyncManager`): local-first, then CloudKit with **last-write-wins** merge; debounced; reloads widget timelines (`WidgetCenter.shared.reloadAllTimelines()`) and refreshes `ASCredentialIdentityStore` after every mutation. Use `SyncState` for UI status. Account mutations should go through `SyncManager`, not `SharedDataManager` directly, so cloud + widget + AutoFill stay consistent.
- **Widget** (`TOTP Widget/`): `AppIntentTimelineProvider` emits entries every 30s for ~5 min (`policy: .atEnd`); it can't reach the clipboard (uses App Intents / URL schemes). Gate widget views with the same `@available` as the app.
- **AutoFill** (`TOTP AutoFill/`): `ASOneTimeCodeCredentialIdentity` (+ optional `ASPasswordCredentialIdentity` when an account has a prefix). Service identifiers come from associated domains, falling back to a normalized issuer.
- **macOS**: `MenuBarExtra` (`.window` style) menu bar mode, ⌘, `Settings` scene, launch-at-login via `SMAppService.mainApp`, Dock-icon policy via `NSApp.setActivationPolicy`. macOS-only behavior is in `MenuBarView`, `SettingsView`, `MacOSAppSettings`, and `MacAppDelegate`.

## Testing

- Framework: **Swift Testing** (`import Testing`, `@Test`, `#expect`) for unit tests; **XCUITest** for UI tests.
- HOTP **must** be validated against RFC 4226 test vectors (see `TOTPTests/TOTPTests.swift`). Any change to OTP generation requires those vectors to still pass.
- Add regression tests for bug fixes; add RFC/round-trip tests for crypto changes (encrypt→decrypt should be identity).

## Do / Don't

**Do:** keep cross-platform parity (build iOS *and* macOS); add `@available(iOS 26.0, macOS 26.0, *)` to new views; route platform code through the shims; encrypt before persisting; run the suite after touching `Generator/` or `Model/`; update previews when editing views.

**Don't:** add third-party dependencies; use `.foregroundColor` / `.spring()` / `.shadow()` (use `.foregroundStyle` / `.smooth` / background contrast); put `.glassEffect()` on cards; store or log secrets in plaintext; change an identifier in only one place; assume CloudKit/AutoFill work in an unsigned simulator build.

## Conventions

- **Commits:** Conventional Commits — `type(scope): subject`. Types: `feat|fix|docs|style|refactor|test|chore`. Scopes: `app|widget|autofill|otp|storage|sync|ui|security|macos`. (e.g. `fix(otp): correct HOTP counter increment`).
- **Roadmap / feature status:** [docs/RFE.md](docs/RFE.md).
- Don't commit or push unless asked. Branch before committing on `main`.

## Harness in this repo

- **Skills** (`.claude/skills/`): `build-run-totp` (build & launch on iOS Simulator or macOS), `test-totp` (run unit/UI tests). The built-in `/run` and `verify` skills will discover these.
- **Settings** (`.claude/settings.json`): allowlists safe `xcodebuild`/`swift`/`git`/`simctl` commands so common build/test calls don't prompt. Personal overrides go in `.claude/settings.local.json` (git-ignored).
