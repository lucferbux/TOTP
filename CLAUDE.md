# CLAUDE.md

Guidance for Claude Code working in this repository. This is the single source of truth for working
conventions. [AGENTS.md](AGENTS.md) is the portable summary for other agents — **update both together.**

## Project Overview

**TOTP Password** — a native, multi-platform SwiftUI authenticator that generates 2FA codes per **RFC 4226 (HOTP)** and **RFC 6238 (TOTP)**. Single codebase shipping to **iPhone, iPad, and Mac** (Universal Purchase), with **iCloud/CloudKit sync**, a **home-screen Widget**, an **AutoFill credential provider**, a **macOS menu bar** mode, and a read-only **Apple Watch app** with a complication (embedded in the iOS app). No third-party dependencies — 100% Apple frameworks.

- **Language / mode:** Swift (Swift 5 language mode — `SWIFT_VERSION = 5.0`)
- **UI:** SwiftUI with the **iOS 26 "Liquid Glass"** design language
- **Deployment targets:** iOS/iPadOS **27.0+**, macOS **27.0+**, watchOS **27.0+** (visionOS 27 is also a supported platform)
- **Toolchain:** Xcode **27.x** (this machine: Xcode 27.2)
- **Crypto:** CryptoKit — HMAC SHA-1/256/512 for OTP, `ChaChaPoly` for at-rest encryption


## Build, Run & Test

The project file is `TOTP.xcodeproj` (no `.xcworkspace`, no SPM/Cocoapods).

| Target | Scheme | Bundle ID |
|--------|--------|-----------|
| Main app | `TOTP` | `com.lucferbux.TOTP` |
| Widget extension | `TOTP WidgetExtension` | `com.lucferbux.TOTP.TOTP-Widget` |
| AutoFill extension (iOS + macOS) | (via `TOTP`) | `com.lucferbux.TOTP.TOTP-Autofill` |
| Watch app (embedded in the iOS app) | `TOTP Watch` | `com.lucferbux.TOTP.watchkitapp` |
| Watch complication (WidgetKit, in the watch app) | (via `TOTP Watch`) | `com.lucferbux.TOTP.watchkitapp.widget` |
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

# Build the watch app (the iOS build above also builds and embeds it in TOTP.app/Watch/)
xcodebuild build -project TOTP.xcodeproj -scheme "TOTP Watch" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 4 (49mm)'

# Run the full test suite (unit + UI) on iOS Simulator
xcodebuild test -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# Run only the unit tests
xcodebuild test -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:TOTPTests
```

- Pick a destination that actually exists: `xcrun simctl list devices available`. iPad-class verification: `name=iPad Pro 11-inch (M5)`. Foldable: `name=iPhone Duo`. Device names exist on several runtimes (27.0, 27.1 for iPhone Duo, and 27.2), so add `OS=27.2` to the destination to pick the latest.
- **iPhone Duo poses** can only be changed in **Device Hub** (Xcode ▸ Open Developer Tool ▸ Device Hub — Xcode 27 has no separate Simulator app); neither `simctl` nor XCTest can fold it. It boots closed. `xcrun simctl io <udid> enumerate` lists both displays (outer 1398×2034, inner 2007×2853), and `simctl io screenshot --display=<port UUID>` captures either. Don't use `simctl io screenConfig … power off` to fake a pose: it blanks both displays until a reboot.
- Run UI tests with `-parallel-testing-enabled NO` on a freshly created simulator: the clones xcodebuild makes otherwise time out while the simulator finishes its first boot.
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
Shared/                    # Compiled into app + widget + AutoFill + both watch targets (file-system synchronized
                           # group; the watch targets exclude EncryptionKeyManager and ClipboardManager)
├── OTP/HOTP.swift         # hotpCode() → zero-padded String; OtpAlgorithm (SHA1/256/512)
├── OTP/OTP.swift          # OtpEntry (.hotp/.totp + algorithm), code(at:), countdown helpers, CodeTimeline
├── Model/OtpModel.swift   # Account model; autoFillValue() = prefix + code; AutoFill domain matching
├── Model/AccountStore.swift        # StoredOtpAccount + ChaChaPoly codec; read-only loader for extensions
├── Model/EncryptionKeyManager.swift# Single owner of the at-rest key
├── Model/OtpAuthURL.swift # otpauth:// parse/build
├── Model/WatchPayload.swift        # iPhone → watch payload (TOTP only, no prefix/domains) + the watch's sealed cache
├── Model/SampleAccounts.swift      # Fictional UI-test / screenshot seeds, shared by the app and the watch
├── Model/Data+Base32.swift
└── Platform/ClipboardManager.swift # Every copy goes here (auto-clear); AppPreferences (App Group)
SharedIntents/             # App + widget: AccountEntity (IndexedEntity), GetCodeIntent, CopyCodeIntent
TOTP/
├── TOTPApp.swift          # @main; WindowGroup + commands (⌘N via FocusedValues) + macOS MenuBarExtra/Settings
├── Model/                 # SharedDataManager (local), CloudKitDataManager, CloudKitOtpModel, SyncManager,
│                          # WatchSyncManager (iOS only: WatchConnectivity sender)
├── View/                  # ContentView (List ⇄ adaptive grid by size class), AccountCodeView, AddingPageView,
│                          # QRScannerView, SettingsView (iOS sheet + macOS ⌘,), MenuBarView (macOS)
├── Intents/TOTPShortcuts.swift  # AppShortcutsProvider (app only)
└── Helper/                # AppLockManager (LocalAuthentication), PlatformUtilities, MacOSAppSettings
TOTP Widget/               # Single + multi account widgets, Lock Screen families, CopyCodeControl (Control Center)
TOTP AutoFill/             # ASCredentialProviderViewController (iOS + macOS), OTPSelectionView
TOTP Watch/                # watchOS app: WatchAccountsModel (WCSession receiver), AccountListView, AccountDetailView
TOTP Watch Widget/         # watchOS complication (accessory families, AppIntentConfiguration account picker)
Watch Shared/              # Both watch targets: WatchKeyStore (the watch's own device-only key), code formatting
TOTPTests/ , TOTPUITests/  # Swift Testing unit tests + XCUITest UI tests (`-UITestMode`)
docs/                      # ARCHITECTURE.md, CONTRIBUTING.md, RFE.md (roadmap)
```

### Identifiers (must stay in sync across targets & entitlements)

- **App Group:** `group.com.lucferbux.TOTP` — the only channel for app↔widget↔autofill data sharing
- **Keychain access group:** `$(AppIdentifierPrefix)com.lucferbux.TOTP` — shared encryption key lives here
- **iCloud container:** `iCloud.com.lucferbux.TOTP` (CloudKit + CloudDocuments)
- **Encryption-key Keychain service:** `TOTP-Shared-Encryption` (synchronizable, one item per key). `TOTP-SharedData-Encryption` and `TOTP-CloudKit-Encryption` are legacy (device-local `master-key` items from older builds): still read so their data can be re-sealed, never written.
- **Watch:** bundle ids `com.lucferbux.TOTP.watchkitapp` (+ `.widget`); `WKCompanionAppBundleIdentifier = com.lucferbux.TOTP`. Both watch targets use App Group `group.com.lucferbux.TOTP` (a separate container on the watch) and Keychain access group `$(AppIdentifierPrefix)com.lucferbux.TOTP.watchkitapp` (service `TOTP-Watch-Encryption`).

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
//  • regular (iPad, iPhone Duo open, Mac) — every action lives in the navigation bar: add
//    (.visibilityPriority(.high)), then "Select Accounts" in the system ToolbarOverflowMenu on iOS
//    (the ellipsis belongs to it; XCUITest sees it as "OverflowBarButtonItem", or "TopOverflowBarButtonItem" from iPadOS 27.2). On macOS,
//    where ToolbarOverflowMenu doesn't exist, it's a plain toolbar button ("selectButton") — a menu
//    holding one item felt ported. ToolbarSpacer doesn't exist on visionOS: guard it. Search keeps
//    its default position.
//  • iPhone Duo puts bars on the side (outer display, inner in landscape). An item with a title but
//    no symbol never goes there, so every toolbar item has both: Button("Select", systemImage:),
//    Button("Done", systemImage: "checkmark", role: .confirm), Cancel with "xmark", and so on.
// Select mode ("Select" on iPhone, ⋯ ▸ Select Accounts on iPad, the Select Accounts button on Mac) replaces add with a destructive
// trash button + "Done", and the leading item with "Select All"; the trash carries an
// accessibilityLabel with the count, since the glyph alone can't show it. On compact widths selection is driven by List(selection:) with editMode
// active; the grid uses its own checkmarks so iPad/Mac behave the same.

// Layout adapts through size classes only — never idiom, orientation or screen size
// (iPhone Duo: outer display compact, inner display regular×regular, ignores orientation locks):
@Environment(\.horizontalSizeClass) var sizeClass  // compact → List, regular → LazyVGrid
AccountGridLayout.columns(for: fold)               // 300–480 pt cards; on a display that folds
                                                   // (iPhone Duo) an even count, and while it's
                                                   // half open the cards on each side stop at the
                                                   // fold (FoldGeometry reads reservedRegions, 27.1)
// List and grid share .scrollPosition(id:), so folding or unfolding keeps the same accounts in view.
// iOS 27.1 ships only on iPhone Duo: the deployment target stays 27.0 and 27.1 APIs need #available.

// Cards (regular-width grid) — native surface, NOT glass:
.background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PlatformColors.secondarySystemGroupedBackground) }

// Liquid Glass only on floating, transient chrome (toasts, overlays), never on cards.
// Use the shared helpers — the raw modifiers don't exist on visionOS:
.floatingGlass(in: .capsule)      // instead of .glassEffect(.regular, in:)
.prominentActionStyle()           // instead of .buttonStyle(.glassProminent)

// Modern modifiers:
TimelineView(.codeTicks(paused: !liveCodesEnabled)) // never Timer.publish or .periodic(from: .now, …):
                                                // ticks on whole seconds (all rows in one frame) and
                                                // stops while the window is hidden or locked
// Nothing animates every second — on a Mac each animated frame re-lays out the whole window
// (~30% CPU with three accounts). The countdown ring steps; only the code (every 30 s) animates.
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
- **Never mint an encryption key on a failed read.** `EncryptionKeyManager` separates *absent* from *unavailable*; only "absent everywhere" may create a key, Keychain keys are only ever **added** (`SecItemAdd` — never `SecItemUpdate` or `SecItemDelete`: deleting a synchronizable item removes it from every device, and overwriting one loses a key), and an existing key file is never overwritten (only the mirror is replaced, after its old key is retired).
- **Never drop ciphertext you can't read.** Undecryptable records are preserved byte-for-byte on save; a partially readable store is never re-sealed.
- **Extensions honour the app lock**: with it on, AutoFill, Shortcuts and the Control authenticate before handing over a code — AutoFill before it even draws its list, which shows live codes. Intents that return or copy a code also declare `authenticationPolicy = .requiresAuthentication`, so a locked device never hands one out. On macOS the lock overlay also disables and hides the content underneath from VoiceOver and keyboard focus.
- **Reading never mints a key.** Only `primaryKey` (about to seal) may create one; `allKeys`, `usesSharedKey` and decryption only report what exists — a new device's first sync must not race the shared key iCloud Keychain hasn't delivered yet. A key replaced in the mirror file is kept in `.totp-encryption-keys-retired` and stays in `allKeys`. In iCloud Keychain every key has its **own item** (`key-<ms>-<uuid>`, added, never updated or deleted); the oldest by name (the ≤4.4 `shared-key` item first) is primary on every device, so devices that each created a key converge without losing either.
- **HOTP never leaves the app**: widgets, intents, controls, AutoFill (picker and credential identities) *and the Apple Watch* list TOTP only, because handing out an HOTP code must advance and persist the counter.
- **Never** log, `print`, or put OTP keys / prefixes / generated codes into analytics, error messages, or screenshots. Use `os.Logger` without account data.
- The prefix (PIN) is never displayed; the UI shows a "PIN" badge only. App Intent entities expose issuer/name only.
- Never write a secret to `UserDefaults` unencrypted. The widget and AutoFill extension decrypt independently using the shared Keychain key.

## Subsystem notes

- **OTP math** (`Shared/OTP/`) is pure and platform-free — keep it that way so it stays unit-testable. `code(at:)` never mutates; HOTP is advanced explicitly via `SyncManager.useCode(for:)` (which persists the counter). Codes are zero-padded `String`s — never format them from integers.
- **Shared code**: anything the widget/AutoFill need goes in `Shared/` (or `SharedIntents/` for App Intents). Don't duplicate models in extensions.
- **Sync** (`SyncManager` + `CloudKitDataManager`): local-first, then CloudKit. **Last write wins per account**: `OtpModel.modifiedDate` changes only on an edit or an HOTP use (`SyncManager.updateAccount` / `useCode` stamp it; saving or uploading never does), and `SyncManager.reconcile` / `OtpModel.resolved` keep the later copy in both directions — except that an HOTP counter never moves backwards for the same secret. CloudKit save conflicts are resolved the same way instead of overwriting the server. Cloud-only accounts are added. Account mutations go through `SyncManager`, never `SharedDataManager` directly, so cloud + widget + AutoFill + Spotlight stay consistent. Use `SyncState` for UI status.
  - `SyncManager`, `SharedDataManager` and `CloudKitDataManager` are `@MainActor`. Never carry a snapshot of `localManager.accounts` across an `await` — re-read it.
  - One sync pass at a time (`performSync()` coalesces callers). Single-account CloudKit writes run in order through `writeToCloud`; `useCode(for:)` advances and saves an HOTP counter synchronously before anything can suspend.
  - Deletions are recorded in `pending_cloud_deletions` (App Group) until CloudKit confirms them, so an offline delete can't be resurrected by the next sync.
  - Records live in the **`TOTPAccounts` record zone** of the private database and are read with **zone change tokens** (`recordZoneChanges(inZoneWith:since:)`), never `CKQuery`. Queries need QUERYABLE indexes an auto-created schema doesn't have — the 3.x code failed every read with *"Field 'recordName' is not marked queryable"*, so iCloud looked empty forever. Change tokens need no indexes and also report deletions.
  - After a relaunch the in-memory mirror is empty, so the first fetch of a session ignores the saved token and rebuilds from the whole zone; otherwise everything gets re-uploaded.
  - `migrateDefaultZoneRecords(ids:)` moves 3.x records (written to `_defaultZone`) into the zone by record ID — that lookup needs no index either.
  - **Never block sync on other subsystems.** Spotlight donation is fire-and-forget (`scheduleSpotlightIndexing()`); awaiting it once hung launch before iCloud was ever contacted.
- **Widget** (`TOTP Widget/`): `AppIntentTimelineProvider` emits entries aligned to period boundaries (`CodeTimeline`) for 10 periods (`policy: .atEnd`); codes are computed from `entry.date`. Tap-to-copy is `Button(intent: CopyCodeIntent)`. Widgets/intents/controls only list TOTP accounts (HOTP counters must be advanced by the app). Codes use `.privacySensitive()`. With the app lock on, the widget shows a `.locked` state and never decrypts anything; empty and locked timelines use `policy: .never` (the app reloads timelines on every change and lock toggle).
- **AutoFill** (`TOTP AutoFill/`, iOS + macOS): `ASOneTimeCodeCredentialIdentity` (+ `ASPasswordCredentialIdentity` when an account has a prefix). One-time-code requests complete with `ASOneTimeCodeCredential`; password requests with `ASPasswordCredential(password: prefix + code)`. Service identifiers come from associated domains, falling back to a normalized issuer.
- **CloudKit schema**: the optional `algorithm` field is only written for non-SHA-1 accounts. New fields must be deployed to the Production schema in the CloudKit Console before release. Setup, deployment and troubleshooting live in [docs/CLOUDKIT.md](docs/CLOUDKIT.md) — including why the Console's record browser needs a `recordName` QUERYABLE index that the app must never depend on.
- **macOS**: `MenuBarExtra` (`.window` style) menu bar mode with a **static** icon (macOS 27 hosts all status items in one window; don't animate it), ⌘, `Settings` scene, launch-at-login via `SMAppService.mainApp`, the main window opens on launch unless launch at login is on (`MacOSAppSettings.presentsWindowAtLaunch` — a launch that showed only a menu bar icon, possibly hidden by the notch, left App Review with nothing to look at), Dock-icon policy via `NSApp.setActivationPolicy`. macOS-only behavior is in `MenuBarView`, `SettingsView`, `MacOSAppSettings`, and `MacAppDelegate`.
  - **Menus** (`AccountCommands` in `TOTPApp.swift`): File ▸ Add Account (⌘N), Edit ▸ Select Accounts / Delete Selected Accounts (⌘⌫), Accounts ▸ Sync Now (⌘R) and Copy <issuer> (⌘1…⌘9), Help ▸ support and suggestions. The focused window publishes what they act on through `FocusedValues` (`addAccountAction`, `mainWindowActions`); add new commands the same way. Esc leaves select mode (`onExitCommand`), ⌫ asks to delete the selection (`onDeleteCommand`).
  - **Settings** is a `TabView` of `Form(.grouped)` panes (General, Security, iCloud, AutoFill, About); the iOS sheet is one Form. Diagnostics (CloudKit environment, container) sit in a collapsed group. Opening Settings never starts a sync; Sync Now does.
  - Adding from a QR image: a file importer on Mac (a photo library isn't where Mac users keep setup codes) and drag and drop onto the add sheet or the empty window, through `QRCodeDecoder.otpAuthURL(inImageData:)`.
  - Menu bar panel: search is focused when it opens, ↑/↓ move the highlight, Return copies, Esc clears.
- **Select mode** (`ContentView`): `isSelecting` + `selection: Set<UUID>` drive batch delete through `SyncManager.deleteAccounts(withIds:)`, which removes them locally in one write, deletes each from CloudKit, then refreshes widgets, AutoFill and Spotlight once. Always confirm before deleting.
- **Suggestions and coffee** (`SettingsView`, `TipJarManager`, `TipJarView`): "Send a Suggestion" is a link to a GitHub issue, not a form that posts somewhere, because the app, its privacy policy and its App Store label all promise no network requests of its own and no data collected. "Buy Me a Coffee" is three consumable in-app purchases (Guideline 3.1.1) that unlock nothing; never add Ko-fi or other payment links inside the app. Product ids live in `TipJarManager`, `StoreKit/Tips.storekit` (used by the scheme's Run action and `TipJarTests`) and App Store Connect (`fastlane tips`): keep the three in step. A successful purchase can only be tested in sandbox, from TestFlight.
- **Apple Watch** (`TOTP Watch/`, `TOTP Watch Widget/`, `Watch Shared/`): read-only — a list (issuer, name, grouped code, countdown ring), a large-code detail and a complication (circular, rectangular, inline, corner) for one chosen account. No adding or editing on the watch. Data path: `WatchSyncManager` (iOS only, started from `SyncManager.initializeSync`) sends a versioned `WatchPayload` with `updateApplicationContext` after every mutation (`afterMutation`), `moveAccounts`, `appLockDidChange` and on session activation / watch-state changes; skipped in UI-test mode. Security model:
  - Only TOTP accounts, and only what a code needs (id, issuer, name, secret, digits, period, algorithm, order) — **never the prefix (PIN), never associated domains, never HOTP**.
  - **App lock on → no accounts are sent**, only `isLocked`; the watch wipes its stored copy and shows "Locked on iPhone".
  - The watch seals what it receives with **its own key**, never the iPhone's: `WatchKeyStore`, a Keychain item that is non-synchronizable and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, in the access group the watch app and complication share. `EncryptionKeyManager` isn't compiled into the watch targets, so nothing there can mint or publish the shared synchronizable key. Only the app creates the watch key; the complication only reads it, and an unreadable key is never replaced.
  - The sealed copy (`AccountStore` codec) lives in the watch's App Group defaults, so the complication can read it; `WatchAccountCache.load` filters HOTP again. Losing the key or the copy costs nothing — the iPhone resends.
  - Codes are `.privacySensitive()` and masked ("••• •••") in always-on (`isLuminanceReduced`). The complication's timeline follows the iOS widget (10 periods, `.atEnd`; locked/empty `.never`); the watch app reloads timelines when new context arrives.
  - `-ScreenshotMode` (DEBUG only) seeds `SampleAccounts.screenshot` in memory through the same payload path; `-ScreenshotScene detail` opens the first account.
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
- **App Store metadata** (`fastlane/`): listing copy lives in `fastlane/metadata/{ios,mac}/<locale>/*.txt` (en-US, es-ES, de-DE, fr-FR) and is pushed with `fastlane metadata`. App-level fields (name, subtitle, privacy URL, categories) are shared across platforms by App Store Connect, so they live **only** in the iOS tree — duplicating them lets one lane overwrite the other platform. No lane ever submits for review. Screenshots come from `scripts/export-screenshots.sh`: iPhone and iPad from the UI tests, Mac by relaunching the app per shot with `-ScreenshotMode -ScreenshotScene <select|add>` (both `#if DEBUG` only), Apple Watch (`--watch`) with `xcrun simctl launch <udid> com.lucferbux.TOTP.watchkitapp -ScreenshotMode [-ScreenshotScene detail]` because macOS UI automation needs Accessibility permission. The app reports the window frame it actually got to the App Group container, so the capture never assumes a rect. `whatsNew` can't be set on a first version, and the build is attached separately from the metadata. See [docs/RELEASE.md](docs/RELEASE.md).
- **Icon and App Store art**: `scripts/make-icon.swift` draws the app icon into `TOTP/Assets.xcassets/AppIcon.appiconset` (and, given a second directory, the single 1024 px watchOS icon into `"TOTP Watch/Assets.xcassets/AppIcon.appiconset"`), and `scripts/make-creative-assets.swift` draws the header and search results images into `fastlane/creative_assets/` (upload them in App Store Connect ▸ the version page ▸ Header and Search Results). The second needs `fastlane/screenshots_raw/en-US`, which isn't in git. `fastlane/screenshots_review/tips.png` is the screenshot App Review needs for each in-app purchase, from `TipJarUITests`.
- **Framed App Store screenshots**: `scripts/export-screenshots.sh --locales …` writes raw captures to `fastlane/screenshots_raw/<locale>/` and `fastlane/screenshots_mac_raw/<locale>/` (git-ignored), then `scripts/frame-screenshots.swift` composes the App Store images (icon gradient, headline + subheadline from `fastlane/screenshot_captions/<locale>.json`, the capture in a device frame drawn in code — no downloaded bezels) into `fastlane/screenshots/<locale>/` and `fastlane/screenshots_mac/<locale>/`, which `screenshots_upload` reads. In `-ScreenshotMode` the app looks signed in (synced a minute ago, shared key, every account in iCloud); never show anything real. Scenes that only a localized label could reach open with `-ScreenshotScene` instead.
- **Localization** (en, es, de, fr): one String Catalog per target folder (`TOTP/Localizable.xcstrings` + `AppShortcuts` + `InfoPlist`, and `Localizable.xcstrings` in the widget, AutoFill and both watch folders) — never one in `Shared/`, which every target compiles, so shared strings appear in each target's catalog. Text that reaches the UI as a `String` (errors, `SyncState.description`, `LabeledContent(value:)`) must use `String(localized:)`; counts use plural variants in the catalog, not ternaries; non-text like "⌘K" or "code + title" uses `Text(verbatim:)`. Refresh the catalogs with `xcodebuild -exportLocalizations -project TOTP.xcodeproj -localizationPath /tmp/loc -exportLanguage es -exportLanguage de -exportLanguage fr` (it builds every platform, visionOS included). Functional UI tests pin `-AppleLanguages (en)`; App Shortcut phrases must keep `${applicationName}`.
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
