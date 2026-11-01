#!/bin/bash
# Runs the screenshot UI tests on the devices App Store Connect still requires, and writes the PNGs
# where fastlane deliver and the website expect them.
#
#   scripts/export-screenshots.sh              # iPhone 6.9" + iPad 13" + iPhone Duo outer + Mac
#   scripts/export-screenshots.sh --duo-inner  # only iPhone Duo's inner display (open it first, see below)
#   scripts/export-screenshots.sh --mac-only   # only the Mac shots
#   scripts/export-screenshots.sh --keep       # keep the .xcresult bundles for inspection
#
# Apple's required classes (everything smaller is scaled automatically):
#   iPhone 6.9"       1320×2868   → fastlane/screenshots/en-US  (deliver picks the display type by pixel size)
#   iPad   13"        2064×2752
#   iPhone Duo outer  1398×2034   (required from April 2027 for apps built with the iOS 27.1 SDK)
#   iPhone Duo inner  2007×2853
#
# The UI tests capture whichever display is in use. The iPhone Duo simulator boots closed, so a normal
# run shoots the outer display. Only Device Hub can open it (neither simctl nor XCTest can change the
# pose): boot "iPhone Duo", open it in Xcode ▸ Open Developer Tool ▸ Device Hub, then run --duo-inner.
#   Mac          2880×1800   → fastlane/screenshots_mac/en-US (needs Screen Recording permission)
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT="TOTP.xcodeproj"
SCHEME="TOTP"
OUT="fastlane/screenshots/en-US"
SITE="site/screenshots"
TMP="${TMPDIR:-/tmp}/totp-screenshots"
KEEP=""; DUO_INNER=""; MAC_ONLY=""
for arg in "$@"; do
    case "$arg" in
        --keep) KEEP=1 ;;
        --duo-inner) DUO_INNER=1 ;;
        --mac-only) MAC_ONLY=1 ;;
    esac
done

rm -rf "$TMP"; mkdir -p "$TMP" "$OUT" "$SITE"

capture() {
    local device="$1"
    local prefix="$2"
    local expected="${3:-}"   # WIDTHxHEIGHT the shots must have, when one device has several displays
local result="$TMP/$prefix.xcresult"
    echo "==> $device"
    # Apple's convention for marketing shots: full bars, full battery, 9:41.
    local udid
    # The newest runtime, since a device name can exist on several: App Review wants the latest OS.
    udid=$(xcrun simctl list devices available -j | /usr/bin/python3 -c "
import json,re,sys
name=sys.argv[1]
version=lambda runtime: [int(n) for n in re.findall(r'\d+', runtime.rsplit('.', 1)[-1])]
runtimes=json.load(sys.stdin)['devices']
for runtime in sorted(runtimes, key=version, reverse=True):
    for d in runtimes[runtime]:
        if d['name'] == name:
            print(d['udid']); sys.exit()
" "$device")
    if [ -n "$udid" ]; then
        xcrun simctl boot "$udid" 2>/dev/null || true
        xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
        xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --wifiMode active --wifiBars 3 2>/dev/null || true
    fi

    xcodebuild test \
        -project "$PROJECT" -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$udid" \
        -only-testing:TOTPUITests/ScreenshotTests \
        -resultBundlePath "$result" \
        -derivedDataPath "$TMP/dd" \
        >"$TMP/$prefix.log" 2>&1 || { echo "   FAILED — see $TMP/$prefix.log"; return 1; }

    local staging="$TMP/$prefix-export"
    xcrun xcresulttool export attachments --path "$result" --output-path "$staging" >/dev/null

    # manifest.json maps the generated file names back to the names the test gave them
    /usr/bin/python3 - "$staging" "$OUT" "$prefix" "$expected" <<'PY'
import json, pathlib, shutil, subprocess, sys
staging, out, prefix, expected = (pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4])
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
        if expected:
            info = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(staging / exported)],
                                  capture_output=True, text=True).stdout.split()
            size = f"{info[-3]}x{info[-1]}"
            if size not in (expected, "x".join(reversed(expected.split("x")))):
                sys.exit(f"   {name} is {size}, expected {expected}: is the iPhone Duo in the right pose?")
        target = out / f"{prefix}-{stem}.png"
        shutil.copyfile(staging / exported, target)
        count += 1
        print(f"   {target.name}")
print(f"   {count} screenshot(s)")
PY
}

if [ -n "$DUO_INNER" ]; then
    capture "iPhone Duo" "duo-inner" "2007x2853"
    exit 0
fi

if [ -z "$MAC_ONLY" ]; then
    capture "iPhone 18 Pro Max" "iphone-69"
    capture "iPad Pro 13-inch (M5)" "ipad-13"
    capture "iPhone Duo" "duo-outer" "1398x2034"
fi

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

    # A failed run must not leave old shots behind for fastlane to upload.
    rm -f "$out_mac"/*.png

    # The largest normal window TOTP owns. Capturing it by id, not by screen rect, means whatever
    # else is on screen can't end up in a shot, even with TOTP behind it or on another Space.
    mac_window_id() {
        xcrun swift - <<'SWIFT'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo(.excludeDesktopElements, kCGNullWindowID) as? [[String: Any]] ?? []
let height = { (window: [String: Any]) in (window[kCGWindowBounds as String] as? [String: Double])?["Height"] ?? 0 }
let own = windows.filter { $0[kCGWindowOwnerName as String] as? String == "TOTP" && $0[kCGWindowLayer as String] as? Int == 0 }
if let window = own.max(by: { height($0) < height($1) }), let id = window[kCGWindowNumber as String] as? Int { print(id) }
SWIFT
    }

    # One launch per shot: every screenshot in an App Store set must be the same size, so the
    # window is always 1440x900 points and only its contents change.
    shoot_mac() {
        local name="$1" scene="$2" file="$out_mac/$1.png" id size
        pkill -x TOTP 2>/dev/null || true
        sleep 2
        if [ -n "$scene" ]; then
            open -n "$app" --args -ScreenshotMode -ScreenshotScene "$scene"
        else
            open -n "$app" --args -ScreenshotMode
        fi
        sleep 13
        id=$(mac_window_id || true)
        [ -z "$id" ] || screencapture -x -o -l "$id" "$file" || true
        pkill -x TOTP 2>/dev/null || true
        if [ ! -s "$file" ]; then
            rm -f "$file"
            echo "   $name capture FAILED — grant Screen Recording to the app running this script"
            return 0
        fi
        # App Store Connect rejects transparency, which the window's rounded corners have.
        sips -s format jpeg -s formatOptions best "$file" --out "$TMP/flat.jpg" >/dev/null
        sips -s format png "$TMP/flat.jpg" --out "$file" >/dev/null
        size=$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixel/{printf "%s ", $2}')
        if [ "$size" = "2880 1800 " ]; then
            printf '   %-18s %s\n' "$name.png" "$size"
        else
            rm -f "$file"
            echo "   $name capture FAILED — window is $size, expected 2880 1800"
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
shot relaunches the app with -ScreenshotScene, which opens it straight in that state, and captures
TOTP's own window by id.

If it was skipped, take the shots by hand (⌘⇧4 then space, click the window) and pad them:
    sips --padToHeightWidth 1800 2880 shot.png --out fastlane/screenshots_mac/en-US/01-codes.png
NOTE
[ -n "$KEEP" ] || rm -rf "$TMP"
