---
name: test-totp
description: Run the TOTP app's unit and UI test suites (Swift Testing + XCUITest) on the iOS Simulator or macOS. Use when asked to run tests, validate OTP/RFC correctness, check the suite passes, or add regression tests.
---

# Test TOTP

- **Unit tests** — `TOTPTests/` — Swift Testing (`import Testing`, `@Test`, `#expect`).
- **UI tests** — `TOTPUITests/` — XCUITest.
- Both run via the `TOTP` scheme.

## Run

```bash
DEV="iPhone 18 Pro"   # or: xcrun simctl list devices available

# Whole suite (unit + UI)
xcodebuild test -project TOTP.xcodeproj -scheme TOTP \
  -destination "platform=iOS Simulator,name=$DEV"

# Unit tests only (fast — pure OTP/crypto/model logic, no UI bootstrap)
xcodebuild test -project TOTP.xcodeproj -scheme TOTP \
  -destination "platform=iOS Simulator,name=$DEV" \
  -only-testing:TOTPTests

# A single test
xcodebuild test -project TOTP.xcodeproj -scheme TOTP \
  -destination "platform=iOS Simulator,name=$DEV" \
  -only-testing:TOTPTests/TOTPTests/testHotpCodeGeneration

# macOS
xcodebuild test -project TOTP.xcodeproj -scheme TOTP -destination 'platform=macOS'

# iPhone Duo (iOS 27.1 runtime — it supports only that device). Boots closed: the UI tests run on the
# outer display. Open it in Device Hub to run them on the inner display.
xcodebuild test -project TOTP.xcodeproj -scheme TOTP \
  -destination "platform=iOS Simulator,name=iPhone Duo" -parallel-testing-enabled NO
```

Run UI tests with `-parallel-testing-enabled NO` on a simulator that was just created: the clones
xcodebuild makes time out (watchdog) while it finishes its first boot.

Pipe through `xcbeautify` when available for readable output.

## What the suite guards

- **RFC 4226 HOTP vectors** (`testHotpCodeGeneration`) — counters 0–5 must map to the canonical codes (755224, 287082, …). Any change under `Generator/` must keep these green.
- HOTP counter increments on each `code()`; TOTP display value stays within `0...interval`.
- `OtpEntry` / `OtpModel` equality and construction.

## Writing tests

```swift
import Testing
import Foundation
@testable import TOTP

@Test func descriptiveName() async throws {
    let result = hotpCode(key: key, digits: 6, counter: 0)
    #expect(result == 755224, "explain the expectation")
}
```

Conventions: add a **regression test** for every bug fix; add **RFC / encrypt→decrypt round-trip** tests for any crypto change; keep `Generator/` logic platform-free so it stays unit-testable. Never put real secrets in tests — use the RFC sample keys.
