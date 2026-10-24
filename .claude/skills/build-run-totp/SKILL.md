---
name: build-run-totp
description: Build and launch the TOTP authenticator app on iOS/iPadOS Simulator or macOS. Use when asked to build, run, launch, screenshot, or smoke-test the TOTP app, or to confirm a change compiles and works in the real app.
---

# Build & Run TOTP

Native SwiftUI app, `TOTP.xcodeproj` (no workspace, no SPM). Scheme `TOTP`, deployment iOS/macOS **27.0+**. Two run surfaces: **iOS/iPadOS Simulator** and **macOS**.

## 1. Pick a destination

```bash
xcrun simctl list devices available        # choose a real device name
```
Defaults that exist on this machine: `iPhone 18 Pro`, `iPad Pro 11-inch (M5)` (iOS 27.0) and `iPhone Duo` (iOS 27.1).

**iPhone Duo.** Xcode 27 has no Simulator app: the window is **Device Hub**
(`open /Applications/Xcode.app/Contents/Applications/DeviceHub.app`), and it's the only way to open,
close or half-fold the device — `simctl` and XCTest can't. It boots closed. Capture either display:
```bash
xcrun simctl io "iPhone Duo" enumerate          # outer 1398×2034, inner 2007×2853 — note each port UUID
xcrun simctl io "iPhone Duo" screenshot --display=<port UUID> /tmp/duo.png
```
Don't fake a pose with `simctl io … screenConfig power off`: it blanks both displays until a reboot.

## 2. Build

Pipe through `xcbeautify` if installed (`command -v xcbeautify`), otherwise run raw.

```bash
# iOS / iPadOS Simulator
xcodebuild build -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# macOS
xcodebuild build -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=macOS'
```

A build-only sanity check without a device: `-destination 'generic/platform=iOS Simulator'`.

## 3. Run

### iOS Simulator
```bash
DEV="iPhone 18 Pro"
xcrun simctl boot "$DEV" 2>/dev/null; open -a Simulator
xcodebuild build -project TOTP.xcodeproj -scheme TOTP \
  -destination "platform=iOS Simulator,name=$DEV" \
  -derivedDataPath /tmp/totp-dd
APP=$(find /tmp/totp-dd/Build/Products -name 'TOTP.app' -path '*Simulator*' | head -1)
xcrun simctl install "$DEV" "$APP"
xcrun simctl launch "$DEV" com.lucferbux.TOTP
# screenshot: xcrun simctl io "$DEV" screenshot /tmp/totp.png
```

### macOS
```bash
xcodebuild build -project TOTP.xcodeproj -scheme TOTP \
  -destination 'platform=macOS' -derivedDataPath /tmp/totp-dd
open "$(find /tmp/totp-dd/Build/Products -name 'TOTP.app' -path '*Debug*' | head -1)"
```

## Notes & gotchas

- **CloudKit / AutoFill / App Groups / Keychain sharing need a signing team and provisioned containers.** In an unsigned simulator build these features degrade gracefully — sync shows `iCloud Disabled`, AutoFill identities don't register. Don't report that as a bug; it's expected without signing.
- macOS also runs as a **menu bar app** (`MenuBarExtra`) — check the menu bar, not just the main window. Settings open with ⌘,.
- Identifiers that must stay aligned across targets: App Group `group.com.lucferbux.TOTP`, Keychain group `com.lucferbux.TOTP`, iCloud `iCloud.com.lucferbux.TOTP`.
- To verify a behavior change end-to-end (not just compilation), prefer the built-in `verify` skill, which drives the running app.
