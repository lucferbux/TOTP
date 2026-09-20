#!/bin/bash
# Runs the screenshot UI tests on the devices App Store Connect still requires, and writes the PNGs
# where fastlane deliver and the website expect them.
#
#   scripts/export-screenshots.sh            # iPhone 6.9" + iPad 13"
#   scripts/export-screenshots.sh --keep     # keep the .xcresult bundles for inspection
#
# Apple's required classes (everything smaller is scaled automatically):
#   iPhone 6.9"  1320×2868   → fastlane/screenshots/en-US  (deliver picks the display type by pixel size)
#   iPad   13"   2064×2752
#   Mac          16:10       → see the note at the end; captured manually
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT="TOTP.xcodeproj"
SCHEME="TOTP"
OUT="fastlane/screenshots/en-US"
SITE="site/screenshots"
TMP="${TMPDIR:-/tmp}/totp-screenshots"
KEEP=${1:-}

rm -rf "$TMP"; mkdir -p "$TMP" "$OUT" "$SITE"

capture() {
    local device="$1"
    local prefix="$2"
    local result="$TMP/$prefix.xcresult"
    echo "==> $device"
    # Apple's convention for marketing shots: full bars, full battery, 9:41.
    local udid
    udid=$(xcrun simctl list devices available -j | /usr/bin/python3 -c "
import json,sys
name=sys.argv[1]
for runtime, devices in json.load(sys.stdin)['devices'].items():
    for d in devices:
        if d['name'] == name:
            print(d['udid']); break
" "$device" | head -1)
    if [ -n "$udid" ]; then
        xcrun simctl boot "$udid" 2>/dev/null || true
        xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
        xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --wifiMode active --wifiBars 3 2>/dev/null || true
    fi

    xcodebuild test \
        -project "$PROJECT" -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,name=$device" \
        -only-testing:TOTPUITests/ScreenshotTests \
        -resultBundlePath "$result" \
        -derivedDataPath "$TMP/dd" \
        >"$TMP/$prefix.log" 2>&1 || { echo "   FAILED — see $TMP/$prefix.log"; return 1; }

    local staging="$TMP/$prefix-export"
    xcrun xcresulttool export attachments --path "$result" --output-path "$staging" >/dev/null

    # manifest.json maps the generated file names back to the names the test gave them
    /usr/bin/python3 - "$staging" "$OUT" "$prefix" <<'PY'
import json, pathlib, shutil, sys
staging, out, prefix = (pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3])
manifest = json.loads((staging / "manifest.json").read_text())
count = 0
for test in manifest:
    for att in test.get("attachments", []):
        name = att.get("suggestedHumanReadableName") or ""
        exported = att.get("exportedFileName") or ""
        if not exported.endswith(".png") or not name:
            continue
        # XCTAttachment names come back as "01-codes_0_<uuid>.png" — keep the part we set.
        stem = name.split("_0_")[0]
        if stem.endswith(".png"):
            stem = stem[:-4]
        target = out / f"{prefix}-{stem}.png"
        shutil.copyfile(staging / exported, target)
        count += 1
        print(f"   {target.name}")
print(f"   {count} screenshot(s)")
PY
}

capture "iPhone 18 Pro Max" "iphone-69"
capture "iPad Pro 13-inch (M5)" "ipad-13"

# A few for the website and the README
copy_site() { [ -f "$OUT/$1" ] && cp "$OUT/$1" "$SITE/$2" && echo "   site/$2"; }
copy_site "iphone-69-01-codes.png"  "iphone-codes.png"
copy_site "iphone-69-03-select.png" "iphone-select.png"
copy_site "ipad-13-01-codes.png"    "ipad-grid.png"

echo
echo "Sizes (App Store Connect rejects anything else):"
for f in "$OUT"/*.png; do
    printf '  %-34s %s\n' "$(basename "$f")" "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"
done

cat <<'NOTE'

Mac screenshots are not captured here: macOS UI testing needs automation permission, and
`screencapture` needs Screen Recording. Take three shots of the Mac app by hand (⌘⇧4, space, click
the window), then run:
    sips -z 1800 2880 --padToHeightWidth 1800 2880 shot.png --out fastlane/screenshots_mac/en-US/01-mac.png
Accepted Mac sizes are 1280×800, 1440×900, 2560×1600 or 2880×1800.
NOTE
[ "$KEEP" = "--keep" ] || rm -rf "$TMP"
