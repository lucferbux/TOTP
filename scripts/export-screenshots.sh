#!/bin/bash
# Runs the screenshot UI tests on the devices App Store Connect still requires, writes the raw captures
# to fastlane/screenshots_raw/<locale> (Mac: fastlane/screenshots_mac_raw/<locale>), then frames them
# with scripts/frame-screenshots.swift into fastlane/screenshots/<locale> and fastlane/screenshots_mac/<locale>,
# where fastlane deliver reads them.
#
#   scripts/export-screenshots.sh                          # iPhone 6.9" + iPad 13" + iPhone Duo outer + Mac, en-US
#   scripts/export-screenshots.sh --locales en-US,es-ES    # the same, once per locale (app run in that language)
#   scripts/export-screenshots.sh --duo-inner              # only iPhone Duo's inner display (open it first, see below)
#   scripts/export-screenshots.sh --mac-only               # only the Mac shots
#   scripts/export-screenshots.sh --watch                  # also the Apple Watch shots (once the watch app exists)
#   scripts/export-screenshots.sh --keep                   # keep the .xcresult bundles for inspection
#
# Apple's required classes (everything smaller is scaled automatically); the framer keeps these sizes:
#   iPhone 6.9"       1320×2868   (deliver picks the display type by pixel size)
#   iPad   13"        2064×2752
#   iPhone Duo outer  1398×2034   (required from April 2027 for apps built with the iOS 27.1 SDK)
#   iPhone Duo inner  2007×2853
#   Apple Watch Ultra  422×514
#   Mac               2880×1800   (needs Screen Recording permission)
#
# The UI tests capture whichever display is in use. The iPhone Duo simulator boots closed, so a normal
# run shoots the outer display. Only Device Hub can open it (neither simctl nor XCTest can change the
# pose): boot "iPhone Duo", open it in Xcode ▸ Open Developer Tool ▸ Device Hub, then run --duo-inner.
#
# Captions live in fastlane/screenshot_captions/<locale>.json. A locale whose raws are missing is framed
# from the en-US raws, so to re-frame after editing captions just run the framer:
#   swift scripts/frame-screenshots.swift --locales en-US,es-ES,de-DE,fr-FR
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT="TOTP.xcodeproj"
SCHEME="TOTP"
RAW="fastlane/screenshots_raw"
MAC_RAW="fastlane/screenshots_mac_raw"
SITE="site/screenshots"
TMP="${TMPDIR:-/tmp}/totp-screenshots"
KEEP=""; DUO_INNER=""; MAC_ONLY=""; WATCH=""; LOCALES="en-US"
while [ $# -gt 0 ]; do
    case "$1" in
        --keep) KEEP=1 ;;
        --duo-inner) DUO_INNER=1 ;;
        --mac-only) MAC_ONLY=1 ;;
        --watch) WATCH=1 ;;
        --locales) shift; LOCALES="${1:?--locales needs a comma-separated list, e.g. en-US,es-ES}" ;;
        --locales=*) LOCALES="${1#--locales=}" ;;
        *) echo "unknown option $1" >&2; exit 1 ;;
    esac
    shift
done
IFS=',' read -r -a LOCALE_LIST <<< "$LOCALES"

rm -rf "$TMP"; mkdir -p "$TMP" "$SITE"

# en-US → en ; en-US → en_US
lang_of() { echo "${1%%-*}"; }
apple_locale_of() { echo "${1//-/_}"; }

# The newest runtime, since a device name can exist on several: App Review wants the latest OS.
udid_for() {
    xcrun simctl list devices available -j | /usr/bin/python3 -c "
import json,re,sys
name=sys.argv[1]
version=lambda runtime: [int(n) for n in re.findall(r'\d+', runtime.rsplit('.', 1)[-1])]
runtimes=json.load(sys.stdin)['devices']
for runtime in sorted(runtimes, key=version, reverse=True):
    for d in runtimes[runtime]:
        if d['name'] == name:
            print(d['udid']); sys.exit()
" "$1"
}

boot_for_marketing() {
    local udid="$1"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    # Apple's convention for marketing shots: full bars, full battery, 9:41.
    xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --wifiMode active --wifiBars 3 2>/dev/null || true
}

capture() {
    local device="$1"
    local prefix="$2"
    local expected="${3:-}"   # WIDTHxHEIGHT the shots must have, when one device has several displays
    local locale="$4"
    local out="$RAW/$locale"
    local result="$TMP/$prefix-$locale.xcresult"
    mkdir -p "$out"
    echo "==> $device ($locale)"
    local udid
    udid=$(udid_for "$device")
    [ -z "$udid" ] || boot_for_marketing "$udid"

    # xcodebuild hands TEST_RUNNER_-prefixed variables to the test runner without the prefix:
    # ScreenshotTests reads SCREENSHOT_LANG / SCREENSHOT_LOCALE and launches the app in that language.
    TEST_RUNNER_SCREENSHOT_LANG="$(lang_of "$locale")" \
    TEST_RUNNER_SCREENSHOT_LOCALE="$(apple_locale_of "$locale")" \
    xcodebuild test \
        -project "$PROJECT" -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$udid" \
        -only-testing:TOTPUITests/ScreenshotTests \
        -resultBundlePath "$result" \
        -derivedDataPath "$TMP/dd" \
        >"$TMP/$prefix-$locale.log" 2>&1 || { echo "   FAILED — see $TMP/$prefix-$locale.log"; return 1; }

    local staging="$TMP/$prefix-$locale-export"
    xcrun xcresulttool export attachments --path "$result" --output-path "$staging" >/dev/null

    # manifest.json maps the generated file names back to the names the test gave them
    /usr/bin/python3 - "$staging" "$out" "$prefix" "$expected" <<'PY'
import json, pathlib, shutil, subprocess, sys
staging, out, prefix, expected = (pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4])
manifest = json.loads((staging / "manifest.json").read_text())
shots = []
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
        shots.append((staging / exported, out / f"{prefix}-{stem}.png"))
# Only now that the run produced shots: drop this device's old raws, so a removed scene can't linger.
if shots:
    for old in out.glob(f"{prefix}-*.png"):
        old.unlink()
for source, target in shots:
    shutil.copyfile(source, target)
    print(f"   {target}")
print(f"   {len(shots)} screenshot(s)")
PY
}

# --- macOS -------------------------------------------------------------------------------------
# No UI-test automation here (that needs Accessibility permission). Instead the app positions its
# own window at 1440x900 points in -ScreenshotMode, which captures at 2880x1800 — an accepted size,
# and -ScreenshotScene opens it directly in the state each shot needs.
# Needs Screen Recording permission for whatever runs this script.
MAC_APP=""
build_mac() {
    [ -z "$MAC_APP" ] || return 0
    echo "==> macOS build"
    if ! xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' \
            -derivedDataPath "$TMP/dd-mac" >"$TMP/mac.log" 2>&1; then
        echo "   build FAILED — see $TMP/mac.log"; return 1
    fi
    MAC_APP=$(find "$TMP/dd-mac/Build/Products" -maxdepth 2 -name 'TOTP.app' -path '*Debug*' | head -1)
}

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

capture_mac() {
    local locale="$1"
    local out_mac="$MAC_RAW/$locale"
    local lang apple_locale
    lang=$(lang_of "$locale"); apple_locale=$(apple_locale_of "$locale")
    mkdir -p "$out_mac"
    build_mac || return 1
    echo "==> macOS ($locale)"

    # A failed run must not leave old shots behind to be framed and uploaded.
    rm -f "$out_mac"/*.png

    # One launch per shot: every screenshot in an App Store set must be the same size, so the
    # window is always 1440x900 points and only its contents change.
    shoot_mac() {
        local name="$1" scene="$2" file="$out_mac/$1.png" id size
        pkill -x TOTP 2>/dev/null || true
        sleep 2
        local args=(-AppleLanguages "($lang)" -AppleLocale "$apple_locale" -ScreenshotMode)
        [ -z "$scene" ] || args+=(-ScreenshotScene "$scene")
        open -n "$MAC_APP" --args "${args[@]}"
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
            printf '   %-34s %s\n' "$file" "$size"
        else
            rm -f "$file"
            echo "   $name capture FAILED — window is $size, expected 2880 1800"
        fi
    }

    shoot_mac "01-codes"  ""
    shoot_mac "02-select" "select"
    shoot_mac "03-add"    "add"
}

# --- Apple Watch -------------------------------------------------------------------------------
# Ready for the watch app: launches it in -ScreenshotMode on the simulator and saves the screen.
# Install the watch app on the simulator first (the iOS build/run installs it on a paired watch).
WATCH_DEVICE="Apple Watch Ultra 4 (49mm)"
WATCH_BUNDLE="com.lucferbux.TOTP.watchkitapp"
capture_watch() {
    local locale="$1"
    local out="$RAW/$locale"
    local udid lang apple_locale
    lang=$(lang_of "$locale"); apple_locale=$(apple_locale_of "$locale")
    mkdir -p "$out"
    echo "==> $WATCH_DEVICE ($locale)"
    udid=$(udid_for "$WATCH_DEVICE")
    if [ -z "$udid" ]; then echo "   skipped — no \"$WATCH_DEVICE\" simulator"; return 0; fi
    boot_for_marketing "$udid"
    if ! xcrun simctl get_app_container "$udid" "$WATCH_BUNDLE" >/dev/null 2>&1; then
        echo "   skipped — $WATCH_BUNDLE isn't installed on that simulator"; return 0
    fi
    shoot_watch() {
        local name="$1" scene="$2" file="$out/watch-$1.png"
        xcrun simctl terminate "$udid" "$WATCH_BUNDLE" 2>/dev/null || true
        local args=(-AppleLanguages "($lang)" -AppleLocale "$apple_locale" -ScreenshotMode)
        [ -z "$scene" ] || args+=(-ScreenshotScene "$scene")
        xcrun simctl launch "$udid" "$WATCH_BUNDLE" "${args[@]}" >/dev/null
        sleep 6
        if xcrun simctl io "$udid" screenshot "$file" >/dev/null 2>&1; then
            printf '   %-34s %s\n' "$file" "$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixel/{printf "%s ", $2}')"
        else
            echo "   watch-$name capture FAILED"
        fi
    }
    rm -f "$out"/watch-*.png
    shoot_watch "01-codes" ""
    shoot_watch "02-detail" "detail"
    xcrun simctl terminate "$udid" "$WATCH_BUNDLE" 2>/dev/null || true
}

# --- Capture -----------------------------------------------------------------------------------
FRAME_ONLY=()
for locale in "${LOCALE_LIST[@]}"; do
    if [ -n "$DUO_INNER" ]; then
        capture "iPhone Duo" "duo-inner" "2007x2853" "$locale"
        FRAME_ONLY=(--only duo-inner)
        continue
    fi
    if [ -z "$MAC_ONLY" ]; then
        capture "iPhone 18 Pro Max" "iphone-69" "" "$locale"
        capture "iPad Pro 13-inch (M5)" "ipad-13" "" "$locale"
        capture "iPhone Duo" "duo-outer" "1398x2034" "$locale"
        [ -z "$WATCH" ] || capture_watch "$locale"
    else
        FRAME_ONLY=(--only mac)
    fi
    capture_mac "$locale"
done

# --- Frame -------------------------------------------------------------------------------------
echo
echo "==> Framing ($LOCALES)"
swift scripts/frame-screenshots.swift --locales "$LOCALES" ${FRAME_ONLY[@]+"${FRAME_ONLY[@]}"}

# A few unframed ones for the website and the README
copy_site() { [ -f "$RAW/en-US/$1" ] && cp "$RAW/en-US/$1" "$SITE/$2" && echo "   site/$2"; }
copy_site "iphone-69-01-codes.png"  "iphone-codes.png"
copy_site "iphone-69-03-select.png" "iphone-select.png"
copy_site "ipad-13-01-codes.png"    "ipad-grid.png"

copy_docs() { [ -f "$1" ] && cp "$1" "docs/assets/$2" && echo "   docs/assets/$2"; }
copy_docs "$RAW/en-US/iphone-69-01-codes.png" "screenshot-iphone.png"
copy_docs "$RAW/en-US/ipad-13-01-codes.png"   "screenshot-ipad.png"
copy_docs "$MAC_RAW/en-US/01-codes.png"       "screenshot-macos.png"

cat <<'NOTE'

Mac capture needs Screen Recording permission for whatever runs this script (System Settings ▸
Privacy & Security ▸ Screen & System Audio Recording). It needs no Accessibility permission: each
shot relaunches the app with -ScreenshotScene, which opens it straight in that state, and captures
TOTP's own window by id.

If it was skipped, take the shots by hand (⌘⇧4 then space, click the window), pad them and re-frame:
    sips --padToHeightWidth 1800 2880 shot.png --out fastlane/screenshots_mac_raw/en-US/01-codes.png
    swift scripts/frame-screenshots.swift --only mac
NOTE
[ -n "$KEEP" ] || rm -rf "$TMP"
