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
#   Mac          2880×1800   → fastlane/screenshots_mac/en-US (needs Screen Recording permission)
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

# --- macOS -------------------------------------------------------------------------------------
# No UI-test automation here (that needs Accessibility permission). Instead the app positions its
# own window at 1440x900 points in -ScreenshotMode, which captures at 2880x1800 — an accepted size,
# and -ScreenshotScene opens it directly in the state each shot needs.
# Needs Screen Recording permission for whatever runs this script.
capture_mac() {
    local out_mac="fastlane/screenshots_mac/en-US"
    mkdir -p "$out_mac"
    echo "==> macOS"
    if ! xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' \
            -derivedDataPath "$TMP/dd-mac" >"$TMP/mac.log" 2>&1; then
        echo "   build FAILED — see $TMP/mac.log"; return 1
    fi
    local app
    app=$(find "$TMP/dd-mac/Build/Products" -maxdepth 2 -name 'TOTP.app' -path '*Debug*' | head -1)

    # One launch per shot: every screenshot in an App Store set must be the same size, so the
    # window is always 1440x900 points and only its contents change. The app reports where AppKit
    # actually put it (it clamps against the menu bar), so the capture never has to assume a rect.
    local frame_file="$HOME/Library/Group Containers/group.com.lucferbux.TOTP/screenshot-window-frame"
    shoot_mac() {
        local name="$1" scene="$2"
        pkill -x TOTP 2>/dev/null || true
        rm -f "$frame_file"
        sleep 2
        if [ -n "$scene" ]; then
            open -n "$app" --args -ScreenshotMode -ScreenshotScene "$scene"
        else
            open -n "$app" --args -ScreenshotMode
        fi
        sleep 13
        local rect="100,100,1440,900"
        [ -s "$frame_file" ] && rect=$(cat "$frame_file")
        screencapture -x -R "$rect" "$out_mac/$name.png"
        pkill -x TOTP 2>/dev/null || true
        if [ -s "$out_mac/$name.png" ]; then
            printf '   %-18s %s (rect %s)\n' "$name.png" "$(sips -g pixelWidth -g pixelHeight "$out_mac/$name.png" | awk '/pixel/{printf "%s ", $2}')" "$rect"
        else
            echo "   $name capture FAILED — grant Screen Recording to the app running this script"
        fi
    }

    shoot_mac "01-codes"  ""
    shoot_mac "02-select" "select"
    shoot_mac "03-add"    "add"
}
capture_mac

# A few for the website and the README
copy_site() { [ -f "$OUT/$1" ] && cp "$OUT/$1" "$SITE/$2" && echo "   site/$2"; }
copy_site "iphone-69-01-codes.png"  "iphone-codes.png"
copy_site "iphone-69-03-select.png" "iphone-select.png"
copy_site "ipad-13-01-codes.png"    "ipad-grid.png"

copy_docs() { [ -f "$1" ] && cp "$1" "docs/assets/$2" && echo "   docs/assets/$2"; }
copy_docs "$OUT/iphone-69-01-codes.png"                "screenshot-iphone.png"
copy_docs "$OUT/ipad-13-01-codes.png"                  "screenshot-ipad.png"
copy_docs "fastlane/screenshots_mac/en-US/01-codes.png" "screenshot-macos.png"

echo
echo "Sizes (App Store Connect rejects anything else):"
for f in "$OUT"/*.png; do
    printf '  %-34s %s\n' "$(basename "$f")" "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{printf "%s ", $2}')"
done

cat <<'NOTE'

Mac capture needs Screen Recording permission for whatever runs this script (System Settings ▸
Privacy & Security ▸ Screen & System Audio Recording). It needs no Accessibility permission: each
shot relaunches the app with -ScreenshotScene, which opens it straight in that state, and the app
writes the window's real frame to the App Group container for the capture to use.

If it was skipped, take the shots by hand (⌘⇧4 then space, click the window) and pad them:
    sips --padToHeightWidth 1800 2880 shot.png --out fastlane/screenshots_mac/en-US/01-codes.png
NOTE
[ "$KEEP" = "--keep" ] || rm -rf "$TMP"
