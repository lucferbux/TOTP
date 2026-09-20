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
scripts/export-screenshots.sh     # iPhone + iPad; Mac shots are manual, see below

# 5. Archive and upload the binaries (the release-totp skill has the full commands)

# 6. Push the listing — both platforms, as drafts
fastlane precheck_all
fastlane metadata
```

Then open App Store Connect, check both versions, attach the builds and submit by hand.

## Mac screenshots

macOS UI tests need automation permission and `screencapture` needs Screen Recording, so these are
captured by hand: ⌘⇧4 then space, click the window, then pad to an accepted 16:10 size:

```bash
sips --padToHeightWidth 1800 2880 shot.png --out fastlane/screenshots_mac/en-US/01-mac.png
```

Accepted Mac sizes: 1280×800, 1440×900, 2560×1600, 2880×1800.

## Notes

- **Screenshots are per platform**, and are not shared by Universal Purchase.
- **`promotional_text`** can be changed without shipping a new version; everything else on the
  version cannot.
- A new CloudKit field needs *Deploy Schema Changes* in the CloudKit Console before release — see
  [CLOUDKIT.md](CLOUDKIT.md).
