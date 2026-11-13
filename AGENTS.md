# AGENTS.md

Guide for AI coding agents working in this repository. Claude Code additionally reads
[CLAUDE.md](CLAUDE.md), which holds the full conventions; this file is the portable summary —
**keep the two in sync when you change either.**

## What this project is

**TOTP Password** — a native SwiftUI authenticator (RFC 4226 HOTP / RFC 6238 TOTP) shipping
from one codebase to iPhone, iPad and Mac (Universal Purchase), with iCloud/CloudKit sync, widgets
and a Control, an AutoFill credential provider, Siri/Shortcuts/Spotlight intents, a macOS menu
bar mode, and a read-only Apple Watch app with a complication (embedded in the iOS app). **No third-party dependencies — 100% Apple frameworks.**

A distinguishing feature: each account may carry a **fixed prefix (PIN)** that is prepended to the
generated code everywhere it is copied or filled. Never break, log or display that value.

- Swift 5 language mode, SwiftUI, Liquid Glass design
- Minimum OS: **iOS/iPadOS 27, macOS 27, watchOS 27, visionOS 27**; build with **Xcode 27+**
- Crypto: CryptoKit (HMAC SHA-1/256/512, `ChaChaPoly` at rest)

## Build, run, test

`TOTP.xcodeproj` — no workspace, no SPM, no CocoaPods. Schemes: `TOTP` (its iOS build also builds
and embeds the watch app in `TOTP.app/Watch/`) and `TOTP Watch`.

```bash
# Build (pick a live device: xcrun simctl list devices available)
xcodebuild build -project TOTP.xcodeproj -scheme TOTP -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
xcodebuild build -project TOTP.xcodeproj -scheme TOTP -destination 'platform=macOS'
xcodebuild build -project TOTP.xcodeproj -scheme "TOTP Watch" -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 4 (49mm)'

# Tests (Swift Testing + XCUITest)
xcodebuild test -project TOTP.xcodeproj -scheme TOTP -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
xcodebuild test ... -only-testing:TOTPTests          # unit only
xcodebuild test ... -only-testing:TOTPUITests        # UI only
```

- Always verify **both** iOS and macOS build before declaring a change done.
- UI tests launch the app with `-UITestMode`: seeded in-memory accounts, no CloudKit, no app lock,
  no AutoFill identity writes. Never point tests at real accounts.
- CloudKit, AutoFill, App Groups and Keychain sharing need signing; in an unsigned simulator build
  they degrade (sync shows "iCloud Disabled"). That is expected, not a regression.
- macOS UI tests need automation permission granted interactively once on the machine.

## Layout

```
Shared/            Compiled into app + widget + AutoFill + watch targets: OTP math, OtpModel, encrypted
                   AccountStore, EncryptionKeyManager, Base32, otpauth:// parser, ClipboardManager,
                   WatchPayload, SampleAccounts (watch targets exclude EncryptionKeyManager/ClipboardManager)
SharedIntents/     App + widget: AccountEntity, Get/Copy Code intents
TOTP/              App: views, SyncManager, CloudKit, AppLockManager, Siri phrases, WatchSyncManager (iOS)
TOTP Widget/       Widgets (home + Lock Screen) and the Control Center control
TOTP AutoFill/     Credential provider extension (iOS + macOS)
TOTP Watch/        watchOS app (read-only list + large code)   TOTP Watch Widget/  complication
Watch Shared/      Both watch targets: WatchKeyStore (watch-only device key)
TOTPTests/         Swift Testing unit tests    TOTPUITests/  XCUITest
```

Identifiers that must stay in sync across targets, entitlements and `pbxproj`:
App Group `group.com.lucferbux.TOTP`, Keychain group `$(AppIdentifierPrefix)com.lucferbux.TOTP`,
iCloud container `iCloud.com.lucferbux.TOTP`, encryption-key Keychain service `TOTP-Shared-Encryption`
(`TOTP-SharedData-Encryption` / `TOTP-CloudKit-Encryption` are legacy, read only). Watch: bundle ids
`com.lucferbux.TOTP.watchkitapp` (+ `.widget`), Keychain group
`$(AppIdentifierPrefix)com.lucferbux.TOTP.watchkitapp`, service `TOTP-Watch-Encryption`.

## Rules

**Security (non-negotiable)**
1. OTP secrets are `ChaChaPoly`-sealed before touching any store (UserDefaults, CloudKit). Plaintext
   keys exist only in memory while generating a code.
2. Never log, `print`, or put secrets, prefixes or generated codes in analytics, errors or test
   fixtures. Use `os.Logger` without account data.
3. Never commit real credentials, issuers, usernames or PINs — not in code, samples, previews,
   tests, fixtures or docs. Use `Example Corp` / `user@example.com` / `JBSWY3DPEHPK3PXP`.
4. The prefix is never rendered on screen; show the "PIN" badge instead. It is secret material:
   sealed before storage or upload, never logged.
5. Extensions only read the encryption key (`EncryptionKeyManager.existingKey()`), never create it.
   A key is minted only when every source is positively absent — an unreadable source is not absent —
   and only to seal something (`primaryKey`); reading (`allKeys`) never mints. Never discard a key
   (replaced ones go to the retired-keys file) and never drop records you can't decrypt.
   Each iCloud Keychain key is its own item (only ever added — no `SecItemUpdate`, no delete); the
   oldest by name is primary everywhere. AutoFill authenticates before drawing its list; widgets show
   a locked state while the app lock is on; HOTP never leaves the app (no widget, intent, control,
   AutoFill or watch).
   Sync is last-write-wins per account on `modifiedDate`, which only an edit or an HOTP use changes.
   **Apple Watch**: the iPhone (`WatchSyncManager`, WatchConnectivity application context) sends
   TOTP accounts only, with just issuer, name, secret, digits, period, algorithm and order — never the
   prefix, associated domains or HOTP — and with the app lock on, no accounts at all (the watch shows
   "Locked on iPhone"). The watch seals them with its **own** non-synchronizable
   `AfterFirstUnlockThisDeviceOnly` Keychain key (`WatchKeyStore`); `EncryptionKeyManager` is not
   compiled into the watch targets. Only the watch app creates that key; the complication only reads it.

**Correctness**
6. Codes are zero-padded `String`s. Never format a code from an integer — leading zeros matter,
   especially with a prefix.
7. Keep `Shared/OTP/` pure and platform-free so it stays unit-testable.
8. Any change to OTP generation must keep the RFC 4226/6238 vectors in
   `TOTPTests/OTPGeneratorTests.swift` passing. Add a regression test with every bug fix.
9. Don't duplicate models in extensions — put shared code in `Shared/`.
10. New CloudKit fields must be deployed to the Production schema before release; write optional
    fields only when they differ from the default.
11. Read CloudKit through zone change tokens, never `CKQuery` — queries need indexes that an
    auto-created schema lacks, and they can't report deletions. See `docs/CLOUDKIT.md`.
12. Never block syncing or launch on another subsystem (Spotlight, push registration); make those
    fire-and-forget. Log failures with `os.Logger` instead of swallowing them.
13. Suggestions stay a link to GitHub and tips stay consumable in-app purchases: the app promises no network requests of its own and no data collected, and Guideline 3.1.1 rules out outside payment links. Product ids live in `TipJarManager`, `StoreKit/Tips.storekit` and App Store Connect (`fastlane tips`).

**UI**
13. Adapt with **size classes only** — never device idiom, orientation or screen size (iPhone Duo:
    outer display compact, inner display regular and it ignores orientation locks).
14. Regular width (iPad, iPhone Duo open, Mac): add, then Select Accounts in the system
    `ToolbarOverflowMenu` on iOS (a plain Select Accounts button on macOS). Every toolbar item has a title
    **and** a symbol — iPhone Duo moves bars to the side, and a title-only item can't go there.
    The grid keeps an even column count on a display that folds and keeps cards off the fold
    (`AccountGridLayout`). iOS 27.1 ships only on iPhone Duo, so the deployment target stays 27.0
    and 27.1 APIs need `#available`. The Mac main window opens at launch unless launch at login
    is on — never ship a launch that shows only a menu bar icon.
15. Prefer system components (`List`, `.swipeActions`, `.searchable`, toolbars,
    `ContentUnavailableView`, `Form`); they get Liquid Glass for free.
16. Liquid Glass only on floating, transient chrome — never on cards or list rows — and through the
    shared helpers `floatingGlass(in:)` / `prominentActionStyle()`, which fall back on visionOS.
17. Use `.foregroundStyle`, `.smooth` animations, `TimelineView(.codeTicks(paused:))`, `#Preview`,
    `@ScaledMetric`. Don't use `.foregroundColor`, `.spring()`, `.shadow()`, `PreviewProvider`,
    `Timer.publish` or `.periodic(from: .now, …)`, and don't animate anything every second — live
    codes pause while the window is hidden or locked (`pausesLiveCodesWhenHidden()`).
    `SyncManager`, `SharedDataManager` and `CloudKitDataManager` are `@MainActor`; never carry a
    snapshot of the account list across an `await`.
18. Every interactive element needs an accessibility label; list rows and controls that tests drive
    need a stable `accessibilityIdentifier`. Icon-only toolbar buttons must spell out any state the
    glyph can't show (e.g. the trash button's selected count).
19. Widgets: Lock Screen accessory families and Controls are iOS/macOS only — guard them so the
    visionOS build keeps compiling.
20. Keep iOS and macOS at parity; route platform differences through the existing shims
    (`PlatformColors`, `ClipboardManager`, `SystemSettings`).

**Release**
21. Listing copy lives in `fastlane/metadata/`; app-level fields (name, subtitle, privacy URL,
    categories) only in the iOS tree, since App Store Connect shares them across platforms.
22. No automation submits for review — lanes leave drafts for a human. Attaching the build is a
    separate step from pushing metadata, and `whatsNew` can't be set on a first version.
23. The website is `site/`, published by GitHub Actions. Never point Pages at `docs/`.
24. Screenshots come from `scripts/export-screenshots.sh`. The Mac shots are driven by
    `-ScreenshotMode -ScreenshotScene <name>` (debug-only launch arguments) rather than UI
    automation, which would need Accessibility permission. The watch app takes the same arguments
    (`-ScreenshotScene detail`); its seeds come from `SampleAccounts` in `Shared/`. Raw captures go
    to `fastlane/screenshots_raw/<locale>/`; `scripts/frame-screenshots.swift` turns them into the
    framed App Store images (captions in `fastlane/screenshot_captions/<locale>.json`).
24b. The app is localized in en, es, de and fr with one String Catalog per target folder, never in
    `Shared/`. UI text that travels as a `String` uses `String(localized:)`; counts use catalog
    plurals; non-text uses `Text(verbatim:)`. Functional UI tests pin `-AppleLanguages (en)`.
24c. Mac menus live in `AccountCommands` and act on the focused window through `FocusedValues`
    (`addAccountAction`, `mainWindowActions`). Mac Settings is a `TabView` of `Form` panes.

**Workflow**
25. Conventional Commits: `type(scope): subject` with
    types `feat|fix|docs|style|refactor|test|chore` and
    scopes `app|widget|autofill|otp|storage|sync|ui|security|macos|intents`.
26. Don't commit or push unless asked. Branch before committing on `main`.
27. Update `CLAUDE.md`, `AGENTS.md`, `README.md` and `docs/RFE.md` when behaviour or structure changes.
28. Don't add third-party dependencies, and don't change an identifier in only one place.

## Release

Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for the app, widget, AutoFill, watch app and
watch widget targets together (10 occurrences each), then archive and upload; the iOS archive must
contain `TOTP.app/Watch/TOTP Watch.app`. See `.claude/skills/release-totp/SKILL.md` for the exact commands.
