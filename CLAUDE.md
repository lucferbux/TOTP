# CLAUDE.md

Guidance for Claude Code working in this repository. This is the single source of truth for working
conventions. [AGENTS.md](AGENTS.md) is the portable summary for other agents — **update both together.**

## Project Overview

**TOTP Password** — a native, multi-platform SwiftUI authenticator that generates 2FA codes per **RFC 4226 (HOTP)** and **RFC 6238 (TOTP)**. Single codebase shipping to **iPhone, iPad, and Mac** (Universal Purchase), with **iCloud/CloudKit sync**, a **home-screen Widget**, an **AutoFill credential provider**, and a **macOS menu bar** mode. No third-party dependencies — 100% Apple frameworks.

- **Language / mode:** Swift (Swift 5 language mode — `SWIFT_VERSION = 5.0`)
- **UI:** SwiftUI with the **iOS 26 "Liquid Glass"** design language
- **Deployment targets:** iOS/iPadOS **27.0+**, macOS **27.0+** (visionOS 27 is also a supported platform)
- **Toolchain:** Xcode **27.x** (this machine: Xcode 27.0)
- **Crypto:** CryptoKit — HMAC SHA-1/256/512 for OTP, `ChaChaPoly` for at-rest encryption


## Build, Run & Test

The project file is `TOTP.xcodeproj` (no `.xcworkspace`, no SPM/Cocoapods).

| Target | Scheme | Bundle ID |
|--------|--------|-----------|
| Main app | `TOTP` | `com.lucferbux.TOTP` |
| Widget extension | `TOTP WidgetExtension` | `com.lucferbux.TOTP.TOTP-Widget` |
| AutoFill extension (iOS + macOS) | (via `TOTP`) | `com.lucferbux.TOTP.TOTP-Autofill` |
| Unit tests | (via `TOTP`) → `TOTPTests` | `com.lucferbux.TOTPTests` |
| UI tests | (via `TOTP`) → `TOTPUITests` | `com.lucferbux.TOTPUITests` |

```bash
# List schemes / targets
xcodebuild -list -project TOTP.xcodeproj

# Build for iOS Simulator
xcodebuild build -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# Build for macOS
xcodebuild build -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=macOS'

# Run the full test suite (unit + UI) on iOS Simulator
xcodebuild test -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# Run only the unit tests
xcodebuild test -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:TOTPTests
```

- Pick a destination that actually exists: `xcrun simctl list devices available`. iPad-class verification: `name=iPad Pro 11-inch (M5)`.
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
Shared/                    # Compiled into app + widget + AutoFill (file-system synchronized group)
├── OTP/HOTP.swift         # hotpCode() → zero-padded String; OtpAlgorithm (SHA1/256/512)
├── OTP/OTP.swift          # OtpEntry (.hotp/.totp + algorithm), code(at:), countdown helpers, CodeTimeline
├── Model/OtpModel.swift   # Account model; autoFillValue() = prefix + code; AutoFill domain matching
├── Model/AccountStore.swift        # StoredOtpAccount + ChaChaPoly codec; read-only loader for extensions
├── Model/EncryptionKeyManager.swift# Single owner of the at-rest key
├── Model/OtpAuthURL.swift # otpauth:// parse/build
├── Model/Data+Base32.swift
└── Platform/ClipboardManager.swift # Every copy goes here (auto-clear); AppPreferences (App Group)
SharedIntents/             # App + widget: AccountEntity (IndexedEntity), GetCodeIntent, CopyCodeIntent
TOTP/
├── TOTPApp.swift          # @main; WindowGroup + commands (⌘N via FocusedValues) + macOS MenuBarExtra/Settings
├── Model/                 # SharedDataManager (local), CloudKitDataManager, CloudKitOtpModel, SyncManager
├── View/                  # ContentView (List ⇄ adaptive grid by size class), AccountCodeView, AddingPageView,
│                          # QRScannerView, SettingsView (iOS sheet + macOS ⌘,), MenuBarView (macOS)
├── Intents/TOTPShortcuts.swift  # AppShortcutsProvider (app only)
└── Helper/                # AppLockManager (LocalAuthentication), PlatformUtilities, MacOSAppSettings
TOTP Widget/               # Single + multi account widgets, Lock Screen families, CopyCodeControl (Control Center)
TOTP AutoFill/             # ASCredentialProviderViewController (iOS + macOS), OTPSelectionView
TOTPTests/ , TOTPUITests/  # Swift Testing unit tests + XCUITest UI tests (`-UITestMode`)
docs/                      # ARCHITECTURE.md, CONTRIBUTING.md, RFE.md (roadmap)
```

### Identifiers (must stay in sync across targets & entitlements)

- **App Group:** `group.com.lucferbux.TOTP` — the only channel for app↔widget↔autofill data sharing
- **Keychain access group:** `$(AppIdentifierPrefix)com.lucferbux.TOTP` — shared encryption key lives here
- **iCloud container:** `iCloud.com.lucferbux.TOTP` (CloudKit + CloudDocuments)
- **Encryption-key Keychain service:** `TOTP-SharedData-Encryption`

If you add a target or change an identifier, update **every** `*.entitlements` file plus the `pbxproj` consistently.

## Coding Standards

### OS 27 / Liquid Glass design language (REQUIRED)

The minimum OS is 27, so no `@available` gating is needed for 26/27 APIs.

```swift
// Prefer system components; they get Liquid Glass automatically:
NavigationStack + .searchable + .toolbar { ToolbarItem(placement: .primaryAction) … }
List / .swipeActions / .contextMenu / ContentUnavailableView / Form(.grouped)
.buttonStyle(.glassProminent)                  // prominent call-to-action buttons

// Toolbars, by size class:
//  • compact (iPhone) — Notes-style bottom bar: search on the left, add on the right
//    .toolbar {
//        DefaultToolbarItem(kind: .search, placement: .bottomBar)
//        ToolbarSpacer(.fixed, placement: .bottomBar)
//        ToolbarItem(placement: .bottomBar) { addButton }
//    }
//  • regular (iPad, Mac) — every action lives in the navigation bar next to Select; search keeps
//    its default toolbar position.
// Select mode ("Select" top-right) replaces add with a destructive trash button and the leading
// item with "Select All"; the trash carries an accessibilityLabel with the count, since the glyph
// alone can't show it. On compact widths selection is driven by List(selection:) with editMode
// active; the grid uses its own checkmarks so iPad/Mac behave the same.

// Layout adapts through size classes only — never idiom, orientation or screen size
// (iPhone Duo: outer display compact, inner display regular×regular, ignores orientation locks):
@Environment(\.horizontalSizeClass) var sizeClass  // compact → List, regular → adaptive LazyVGrid
GridItem(.adaptive(minimum: 300, maximum: 480))

// Cards (regular-width grid) — native surface, NOT glass:
.background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PlatformColors.secondarySystemGroupedBackground) }

// Liquid Glass only on floating, transient chrome (toasts, overlays), never on cards.
// Use the shared helpers — the raw modifiers don't exist on visionOS:
.floatingGlass(in: .capsule)      // instead of .glassEffect(.regular, in:)
.prominentActionStyle()           // instead of .buttonStyle(.glassProminent)

// Modern modifiers:
TimelineView(.periodic(from: .now, by: 1))      // never Timer.publish for live codes
.foregroundStyle(.secondary)                    // never .foregroundColor
.animation(.smooth(duration: 0.3), value: x)    // never .spring()
.contentTransition(.numericText())              // for changing codes
.sensoryFeedback(.success, trigger: value)
@ScaledMetric                                   // sizes that follow Dynamic Type
#Preview                                        // PreviewProvider is deprecated in 27
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
ClipboardManager.copy(value)            // always — applies auto-clear
PlatformColors.secondarySystemGroupedBackground
// iOS-only UI: #if os(iOS) ... ; macOS-only (hover, menu bar): #if os(macOS) ...
```

### Naming

- Views `*View`, models `*Model`, managers `*Manager`, extensions `Type+Feature.swift`.
- Types/properties in `lowerCamelCase`/`UpperCamelCase` per the Swift API Design Guidelines.

### State management

`@State` for view-local, `@StateObject` for owned observables (`SyncManager.shared`, `SharedDataManager.shared`), `@ObservedObject` for injected, `@Binding` for parent-owned.

## Security (non-negotiable)

- OTP secret keys are **always** `ChaChaPoly`-sealed before they touch any persistent store (UserDefaults, CloudKit). Plaintext keys live in memory only while generating a code.
- The symmetric key is shared across the user's devices through **iCloud Keychain** (synchronizable item, service `TOTP-Shared-Encryption`), mirrored into the App Group container file for the extensions. Without a shared key, records uploaded by one device can't be decrypted by another. `decryptionKeys` keeps every previously used key so old data still opens, and saving re-seals it with the primary key. It is generated once by `EncryptionKeyManager` and stored as a file in the App Group container (protection `completeUntilFirstUserAuthentication`) so the widget and AutoFill can read it; older Keychain copies are migrated. Extensions only read it (`EncryptionKeyManager.existingKey()`), never create it. Never hard-code or derive keys from constants.
- **Never** commit real credentials — no real issuers, usernames, PINs or secrets in code, previews, samples, tests, fixtures or docs. Use `Example Corp` / `user@example.com` / the RFC test secret. Screenshots use fictional brands only (real ones belong to their owners — App Review 5.2.2).
- **The prefix (PIN) is secret material**, exactly like the seed: sealed before it touches local storage or CloudKit, never logged, never displayed.
- **Never mint an encryption key on a failed read.** `EncryptionKeyManager` separates *absent* from *unavailable*; only "absent everywhere" may create a key, writes use `SecItemUpdate` (deleting a synchronizable item removes it from every device), and an existing key file is never overwritten.
- **Never drop ciphertext you can't read.** Undecryptable records are preserved byte-for-byte on save; a partially readable store is never re-sealed.
- **Extensions honour the app lock**: with it on, AutoFill, Shortcuts and the Control authenticate before handing over a code.
- **Never** log, `print`, or put OTP keys / prefixes / generated codes into analytics, error messages, or screenshots. Use `os.Logger` without account data.
- The prefix (PIN) is never displayed; the UI shows a "PIN" badge only. App Intent entities expose issuer/name only.
- Never write a secret to `UserDefaults` unencrypted. The widget and AutoFill extension decrypt independently using the shared Keychain key.

## Subsystem notes

- **OTP math** (`Shared/OTP/`) is pure and platform-free — keep it that way so it stays unit-testable. `code(at:)` never mutates; HOTP is advanced explicitly via `SyncManager.useCode(for:)` (which persists the counter). Codes are zero-padded `String`s — never format them from integers.
- **Shared code**: anything the widget/AutoFill need goes in `Shared/` (or `SharedIntents/` for App Intents). Don't duplicate models in extensions.
- **Sync** (`SyncManager` + `CloudKitDataManager`): local-first, then CloudKit with **last-write-wins** merge. Account mutations go through `SyncManager`, never `SharedDataManager` directly, so cloud + widget + AutoFill + Spotlight stay consistent. Use `SyncState` for UI status.
  - Records live in the **`TOTPAccounts` record zone** of the private database and are read with **zone change tokens** (`recordZoneChanges(inZoneWith:since:)`), never `CKQuery`. Queries need QUERYABLE indexes an auto-created schema doesn't have — the 3.x code failed every read with *"Field 'recordName' is not marked queryable"*, so iCloud looked empty forever. Change tokens need no indexes and also report deletions.
  - After a relaunch the in-memory mirror is empty, so the first fetch of a session ignores the saved token and rebuilds from the whole zone; otherwise everything gets re-uploaded.
  - `migrateDefaultZoneRecords(ids:)` moves 3.x records (written to `_defaultZone`) into the zone by record ID — that lookup needs no index either.
  - **Never block sync on other subsystems.** Spotlight donation is fire-and-forget (`scheduleSpotlightIndexing()`); awaiting it once hung launch before iCloud was ever contacted.
- **Widget** (`TOTP Widget/`): `AppIntentTimelineProvider` emits entries aligned to period boundaries (`CodeTimeline`) for 10 periods (`policy: .atEnd`); codes are computed from `entry.date`. Tap-to-copy is `Button(intent: CopyCodeIntent)`. Widgets/intents/controls only list TOTP accounts (HOTP counters must be advanced by the app). Codes use `.privacySensitive()`.
- **AutoFill** (`TOTP AutoFill/`, iOS + macOS): `ASOneTimeCodeCredentialIdentity` (+ `ASPasswordCredentialIdentity` when an account has a prefix). One-time-code requests complete with `ASOneTimeCodeCredential`; password requests with `ASPasswordCredential(password: prefix + code)`. Service identifiers come from associated domains, falling back to a normalized issuer.
- **CloudKit schema**: the optional `algorithm` field is only written for non-SHA-1 accounts. New fields must be deployed to the Production schema in the CloudKit Console before release. Setup, deployment and troubleshooting live in [docs/CLOUDKIT.md](docs/CLOUDKIT.md) — including why the Console's record browser needs a `recordName` QUERYABLE index that the app must never depend on.
- **macOS**: `MenuBarExtra` (`.window` style) menu bar mode with a **static** icon (macOS 27 hosts all status items in one window; don't animate it), ⌘, `Settings` scene, launch-at-login via `SMAppService.mainApp`, Dock-icon policy via `NSApp.setActivationPolicy`. macOS-only behavior is in `MenuBarView`, `SettingsView`, `MacOSAppSettings`, and `MacAppDelegate`.
- **Select mode** (`ContentView`): `isSelecting` + `selection: Set<UUID>` drive batch delete through `SyncManager.deleteAccounts(withIds:)`, which removes them locally in one write, deletes each from CloudKit, then refreshes widgets, AutoFill and Spotlight once. Always confirm before deleting.
- **App lock** (`AppLockManager`): optional, off by default, stored in the App Group; locks on background (iOS) or screen lock/sleep (macOS).

## Testing

- Framework: **Swift Testing** (`import Testing`, `@Test`, `#expect`) for unit tests; **XCUITest** for UI tests.
- HOTP/TOTP **must** be validated against the RFC 4226 and RFC 6238 (SHA-1/256/512) vectors in `TOTPTests/OTPGeneratorTests.swift`. Any change to OTP generation requires those vectors to still pass.
- UI tests launch with `-UITestMode` (`AppEnvironment.isUITesting`): seeded in-memory accounts, no CloudKit, no lock, no AutoFill identity writes. Use accessibility identifiers (`account-<Issuer>`, `addAccountButton`, `saveButton`, …).
- Add regression tests for bug fixes; add RFC/round-trip tests for crypto changes (encrypt→decrypt should be identity).

## Do / Don't

**Do:** keep cross-platform parity (build iOS *and* macOS); adapt with size classes; route platform code through the shims; encrypt before persisting; run the suite after touching `Shared/` or `Model/`; update `#Preview`s when editing views.

**Don't:** add third-party dependencies; use `.foregroundColor` / `.spring()` / `.shadow()` / `PreviewProvider` / `Timer.publish`; branch on device idiom, orientation or screen size; put `.glassEffect()` on cards; store or log secrets in plaintext; change an identifier in only one place; assume CloudKit/AutoFill work in an unsigned simulator build.

## Conventions

- **Commits:** Conventional Commits — `type(scope): subject`. Types: `feat|fix|docs|style|refactor|test|chore`. Scopes: `app|widget|autofill|otp|storage|sync|ui|security|macos|intents`. (e.g. `fix(otp): correct HOTP counter increment`).
- **Roadmap / feature status:** [docs/RFE.md](docs/RFE.md).
- Don't commit or push unless asked. Branch before committing on `main`.

## Harness in this repo

- **Skills** (`.claude/skills/`):
  - `build-run-totp` — build & launch on the iOS Simulator or macOS (the built-in `/run` and `verify` skills discover it).
  - `test-totp` — run the unit / UI suites.
  - `release-totp` — version bump, archive and App Store Connect upload (pre-flight checks included).
- **App Store metadata** (`fastlane/`): listing copy lives in `fastlane/metadata/{ios,mac}/en-US/*.txt` and is pushed with `fastlane metadata`. App-level fields (name, subtitle, privacy URL, categories) are shared across platforms by App Store Connect, so they live **only** in the iOS tree — duplicating them lets one lane overwrite the other platform. No lane ever submits for review. Screenshots come from `scripts/export-screenshots.sh`: iPhone and iPad from the UI tests, Mac by relaunching the app per shot with `-ScreenshotMode -ScreenshotScene <select|add>` (both `#if DEBUG` only) because macOS UI automation needs Accessibility permission. The app reports the window frame it actually got to the App Group container, so the capture never assumes a rect. `whatsNew` can't be set on a first version, and the build is attached separately from the metadata. See [docs/RELEASE.md](docs/RELEASE.md).
- **Website** (`site/`): landing page, privacy policy and support page, published to GitHub Pages by `.github/workflows/pages.yml`. Never switch Pages to the `docs/` folder — Jekyll would publish the internal architecture docs as indexable pages.
- **Hooks** (`scripts/swift-guardrails.sh`, wired as a `PostToolUse` hook for `Write|Edit`):
  warns after editing a Swift file that uses `.foregroundColor`, `.spring()`, `.shadow()`,
  `PreviewProvider`, `Timer.publish`, device/screen checks, `print(`, or a hard-coded secret.
  It only warns — fix the warning, don't ignore it. Keep it in sync with the rules above.
- **Settings** (`.claude/settings.json`): allowlists safe `xcodebuild`/`swift`/`git`/`simctl` commands so common build/test calls don't prompt; `xcodebuild -exportArchive` and `git push` always ask. Personal overrides go in `.claude/settings.local.json` (git-ignored).

## Agent checklist

Before saying a change is done:
1. `xcodebuild build` succeeds for **iOS and macOS**.
2. `xcodebuild test -only-testing:TOTPTests` passes (RFC vectors included); UI tests pass when UI changed.
3. New behaviour has a test; every bug fix has a regression test.
4. No secrets, real account data or `print` of codes anywhere — including tests and previews.
5. Docs updated: `CLAUDE.md`, `AGENTS.md`, `README.md`, `docs/RFE.md` as applicable.
