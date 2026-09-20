# AGENTS.md

Guide for AI coding agents working in this repository. Claude Code additionally reads
[CLAUDE.md](CLAUDE.md), which holds the full conventions; this file is the portable summary —
**keep the two in sync when you change either.**

## What this project is

**TOTP Authenticator** — a native SwiftUI authenticator (RFC 4226 HOTP / RFC 6238 TOTP) shipping
from one codebase to iPhone, iPad and Mac (Universal Purchase), with iCloud/CloudKit sync, widgets
and a Control, an AutoFill credential provider, Siri/Shortcuts/Spotlight intents, and a macOS menu
bar mode. **No third-party dependencies — 100% Apple frameworks.**

A distinguishing feature: each account may carry a **fixed prefix (PIN)** that is prepended to the
generated code everywhere it is copied or filled. Never break, log or display that value.

- Swift 5 language mode, SwiftUI, Liquid Glass design
- Minimum OS: **iOS/iPadOS 27, macOS 27, visionOS 27**; build with **Xcode 27+**
- Crypto: CryptoKit (HMAC SHA-1/256/512, `ChaChaPoly` at rest)

## Build, run, test

`TOTP.xcodeproj` — no workspace, no SPM, no CocoaPods. Scheme: `TOTP`.

```bash
# Build (pick a live device: xcrun simctl list devices available)
xcodebuild build -project TOTP.xcodeproj -scheme TOTP -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
xcodebuild build -project TOTP.xcodeproj -scheme TOTP -destination 'platform=macOS'

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
Shared/            Compiled into app + widget + AutoFill: OTP math, OtpModel, encrypted
                   AccountStore, EncryptionKeyManager, Base32, otpauth:// parser, ClipboardManager
SharedIntents/     App + widget: AccountEntity, Get/Copy Code intents
TOTP/              App: views, SyncManager, CloudKit, AppLockManager, Siri phrases
TOTP Widget/       Widgets (home + Lock Screen) and the Control Center control
TOTP AutoFill/     Credential provider extension (iOS + macOS)
TOTPTests/         Swift Testing unit tests    TOTPUITests/  XCUITest
```

Identifiers that must stay in sync across targets, entitlements and `pbxproj`:
App Group `group.com.lucferbux.TOTP`, Keychain group `$(AppIdentifierPrefix)com.lucferbux.TOTP`,
iCloud container `iCloud.com.lucferbux.TOTP`.

## Rules

**Security (non-negotiable)**
1. OTP secrets are `ChaChaPoly`-sealed before touching any store (UserDefaults, CloudKit). Plaintext
   keys exist only in memory while generating a code.
2. Never log, `print`, or put secrets, prefixes or generated codes in analytics, errors or test
   fixtures. Use `os.Logger` without account data.
3. Never commit real credentials, issuers, usernames or PINs — not in code, samples, previews,
   tests, fixtures or docs. Use `Example Corp` / `user@example.com` / `JBSWY3DPEHPK3PXP`.
4. The prefix is never rendered on screen; show the "PIN" badge instead.
5. Extensions only read the encryption key (`EncryptionKeyManager.existingKey()`), never create it.

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
    auto-created schema lacks, and they can't report deletions.
12. Never block syncing or launch on another subsystem (Spotlight, push registration); make those
    fire-and-forget. Log failures with `os.Logger` instead of swallowing them.

**UI**
13. Adapt with **size classes only** — never device idiom, orientation or screen size (iPhone Duo:
    outer display compact, inner display regular and it ignores orientation locks).
14. Prefer system components (`List`, `.swipeActions`, `.searchable`, toolbars,
    `ContentUnavailableView`, `Form`); they get Liquid Glass for free.
15. Liquid Glass only on floating, transient chrome — never on cards or list rows — and through the
    shared helpers `floatingGlass(in:)` / `prominentActionStyle()`, which fall back on visionOS.
16. Use `.foregroundStyle`, `.smooth` animations, `TimelineView`, `#Preview`, `@ScaledMetric`.
    Don't use `.foregroundColor`, `.spring()`, `.shadow()`, `PreviewProvider` or `Timer.publish`.
17. Every interactive element needs an accessibility label; list rows and controls that tests drive
    need a stable `accessibilityIdentifier`.
18. Widgets: Lock Screen accessory families and Controls are iOS/macOS only — guard them so the
    visionOS build keeps compiling.
19. Keep iOS and macOS at parity; route platform differences through the existing shims
    (`PlatformColors`, `ClipboardManager`, `SystemSettings`).

**Workflow**
20. Conventional Commits: `type(scope): subject` with
    types `feat|fix|docs|style|refactor|test|chore` and
    scopes `app|widget|autofill|otp|storage|sync|ui|security|macos|intents`.
21. Don't commit or push unless asked. Branch before committing on `main`.
22. Update `CLAUDE.md`, `AGENTS.md`, `README.md` and `docs/RFE.md` when behaviour or structure changes.
23. Don't add third-party dependencies, and don't change an identifier in only one place.

## Release

Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for the app, widget and AutoFill targets
together, then archive and upload. See `.claude/skills/release-totp/SKILL.md` for the exact commands.
