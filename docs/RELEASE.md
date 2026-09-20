# Releasing TOTP

Binaries are archived and uploaded from a Mac with `xcodebuild` (see
`.claude/skills/release-totp/SKILL.md`); the listing text and screenshots are files in this repo,
pushed with fastlane. Nothing is ever submitted for review automatically.

## One-time setup

### 1. App Store Connect API key
Users and Access ▸ Integrations ▸ **App Store Connect API** ▸ generate a **Team** key with the
*App Manager* role. Download the `.p8` once — it can't be downloaded twice.

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

### 2. Things no API can set
These are App Store Connect UI only, once per app:

| What | Where | Answer for TOTP |
|---|---|---|
| **App Privacy** | App Privacy ▸ Get Started | *No, we do not collect data from this app* → shows **Data Not Collected** |
| **EU trader status (DSA)** | Business ▸ Trader Status | Required for EU distribution; verification takes days |
| **Age rating** | App Information ▸ Age Rating | Everything *None* / *No* → **4+** |
| **Category** | App Information | **Utilities** (must match `LSApplicationCategoryType` in build settings) |
| **Pricing & availability** | Pricing and Availability | — |

### 3. GitHub Pages
Settings ▸ Pages ▸ Source: **GitHub Actions**. The `pages.yml` workflow publishes `site/` on every
push that touches it. Do **not** select the `docs/` folder — that would publish the internal
architecture docs as indexable pages.

## Every release

```bash
# 1. Pre-flight
xcodebuild test -project TOTP.xcodeproj -scheme TOTP -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
xcodebuild test -project TOTP.xcodeproj -scheme TOTP -destination 'platform=macOS' -only-testing:TOTPTests
git status --short            # must be clean

# 2. Version bump — all three shipping targets together (6 occurrences each)
sed -i '' -e 's/MARKETING_VERSION = 4.4;/MARKETING_VERSION = 4.5;/g' \
          -e 's/CURRENT_PROJECT_VERSION = 10;/CURRENT_PROJECT_VERSION = 11;/g' TOTP.xcodeproj/project.pbxproj

# 3. Release notes
$EDITOR fastlane/metadata/ios/en-US/release_notes.txt
cp fastlane/metadata/ios/en-US/release_notes.txt fastlane/metadata/mac/en-US/release_notes.txt

# 4. Screenshots, if the UI changed
scripts/export-screenshots.sh     # iPhone + iPad + Mac

# 5. Archive and upload the binaries (the release-totp skill has the full commands)

# 6. Push the listing — both platforms, as drafts
fastlane precheck_all
fastlane metadata
```

Then open App Store Connect, check both versions, attach the builds and submit by hand.

## Mac screenshots

macOS UI tests need Accessibility permission, which the script doesn't have, so the Mac shots are
driven from launch arguments instead of clicks. `scripts/export-screenshots.sh` relaunches the app
once per shot with `-ScreenshotMode -ScreenshotScene <name>` (`select`, `add`, or nothing for the
plain list); `ContentView.applyScreenshotScene()` opens that state directly. Both flags are
`#if DEBUG` only — a release build ignores them.

The app sizes its own window to 1440×900 points, which captures at 2880×1800. AppKit can still
move it (the menu bar clamps it, and `NSScreen.main` is the *focused* screen, not necessarily the
one being captured), so the app writes the frame it actually ended up with to
`~/Library/Group Containers/group.com.lucferbux.TOTP/screenshot-window-frame` and the script
captures exactly that rect.

The one permission this does need is **Screen Recording**, for whatever runs the script
(System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording). Without it the captures
come out empty and the script says so. To fall back to doing it by hand — ⌘⇧4, space, click the
window — pad the result to an accepted size:

```bash
sips --padToHeightWidth 1800 2880 shot.png --out fastlane/screenshots_mac/en-US/01-codes.png
```

Accepted Mac sizes: 1280×800, 1440×900, 2560×1600, 2880×1800.

## Notes

- **Screenshots are per platform**, and are not shared by Universal Purchase.
- **`release_notes` (What's New) can't be set on a first version** — App Store Connect rejects
  `whatsNew` with `STATE_ERROR` until the app has a released version to describe changes against.
- **The build is attached separately from the metadata.** `fastlane metadata` never picks one; set
  it in App Store Connect, or PATCH `/v1/appStoreVersions/{id}/relationships/build`.
- **App Review contact details** (`fastlane/metadata/*/review_information/`) need a
  `phone_number.txt` and `email_address.txt`. Without them the review-detail record can't be
  created, and deliver's metadata step then dies with "No data" (fastlane #20538) — which is why
  the `screenshots_upload` lane exists as a `skip_metadata` path around it.
- **`promotional_text`** can be changed without shipping a new version; everything else on the
  version cannot.
- A new CloudKit field needs *Deploy Schema Changes* in the CloudKit Console before release — see
  [CLOUDKIT.md](CLOUDKIT.md).
