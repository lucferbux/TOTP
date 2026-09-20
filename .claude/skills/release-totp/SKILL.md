---
name: release-totp
description: Cut a TOTP release — bump the version and build number, archive for iOS and macOS, and upload to App Store Connect. Use when asked to release, ship, archive, bump the version, or send a build to TestFlight / App Store Connect.
---

# Release TOTP

Ships the `TOTP` scheme to App Store Connect for **iOS** and **macOS** from one codebase
(Universal Purchase). Team `7Y2Y846R76`, automatic signing.

## 1. Pre-flight (do not skip)

```bash
xcodebuild test -project TOTP.xcodeproj -scheme TOTP -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
xcodebuild test -project TOTP.xcodeproj -scheme TOTP -destination 'platform=macOS' -only-testing:TOTPTests
git status --short          # working tree must be clean; never archive uncommitted work
```

Also confirm no secrets slipped in:

```bash
grep -rniE "(secret|prefix|pin)\s*[:=]\s*\"[A-Z0-9]{6,}\"" --include="*.swift" .
```

## 2. Bump the version

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` must move **together across the app, widget and
AutoFill targets** (6 occurrences each in `TOTP.xcodeproj/project.pbxproj`; the test targets keep
their own 1.0/1).

```bash
# marketing version x.y, build n (build must be higher than any build already uploaded)
sed -i '' -e 's/MARKETING_VERSION = 4.0;/MARKETING_VERSION = 4.1;/g' \
          -e 's/CURRENT_PROJECT_VERSION = 6;/CURRENT_PROJECT_VERSION = 7;/g' TOTP.xcodeproj/project.pbxproj
grep -c "MARKETING_VERSION = 4.1;" TOTP.xcodeproj/project.pbxproj   # expect 6
```

## 3. Archive

```bash
OUT=<scratchpad>            # never inside the repo
xcodebuild archive -project TOTP.xcodeproj -scheme TOTP -configuration Release \
  -destination 'generic/platform=iOS' -archivePath $OUT/TOTP-iOS.xcarchive -allowProvisioningUpdates
xcodebuild archive -project TOTP.xcodeproj -scheme TOTP -configuration Release \
  -destination 'generic/platform=macOS' -archivePath $OUT/TOTP-macOS.xcarchive -allowProvisioningUpdates

# sanity-check version + embedded extensions
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties" $OUT/TOTP-iOS.xcarchive/Info.plist
ls "$OUT/TOTP-macOS.xcarchive/Products/Applications/TOTP.app/Contents/PlugIns/"   # both .appex present
```

## 4. Upload

`ExportOptions.plist` (write to the scratchpad):

```xml
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>7Y2Y846R76</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
```

```bash
xcodebuild -exportArchive -archivePath $OUT/TOTP-iOS.xcarchive \
  -exportOptionsPlist $OUT/ExportOptions.plist -exportPath $OUT/export-ios -allowProvisioningUpdates
# repeat for TOTP-macOS.xcarchive
```

Uploading is outward-facing and irreversible (a build number can never be reused) — **confirm with
the user before uploading** unless they already asked for it in this session. Report the exact
error rather than working around signing failures.

## 5. After uploading

- Commit the version bump (`chore(app): bump to <version> (<build>)`) and push if asked.
- Remind the user of manual steps: deploy any new CloudKit fields from Development to Production in
  the CloudKit Console, and that App Store Connect processing takes a few minutes before the build
  appears in TestFlight.

## Notes

- visionOS is a supported platform in the project but is not part of the App Store release flow;
  archive it only if explicitly asked.
- `aps-environment` stays `development` in the checked-in entitlements; export rewrites it for
  distribution.
