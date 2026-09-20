#!/bin/bash
# PostToolUse guardrail: warns (never blocks) when a just-edited Swift file breaks a house rule
# from CLAUDE.md / AGENTS.md. Reads the hook JSON payload on stdin.
set -u

payload=$(cat)
file=$(printf '%s' "$payload" | /usr/bin/python3 -c 'import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    print(""); raise SystemExit
print(data.get("tool_input", {}).get("file_path", "") or "")' 2>/dev/null)

case "$file" in
  *.swift) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

warn() { printf 'guardrail (%s): %s\n' "${file##*/}" "$1"; }
found=0
check() { # pattern, message
  if grep -nE "$1" "$file" >/dev/null 2>&1; then warn "$2"; found=1; fi
}

check '\.foregroundColor\(' 'use .foregroundStyle instead of .foregroundColor'
check '\.spring\(' 'use .smooth animations instead of .spring()'
check '\.shadow\(' 'use background contrast instead of .shadow()'
check 'PreviewProvider' 'PreviewProvider is deprecated in OS 27 — use #Preview'
check 'Timer\.publish' 'use TimelineView instead of Timer.publish for live codes'
check 'UIScreen\.main|userInterfaceIdiom|UIDevice\.current\.model' 'adapt with size classes, not device/screen checks'
check 'print\(' 'use os.Logger (and never log codes, prefixes or account data)'

# Secret-shaped literals: long uppercase Base32-ish strings assigned to a secret/prefix/pin
if grep -nEi '(secret|prefix|pin|password)[^=:]*[:=][[:space:]]*"[A-Z2-7]{12,}"' "$file" >/dev/null 2>&1; then
  warn 'looks like a hard-coded secret — use a test vector or Example Corp placeholder'
  found=1
fi

if [ "$found" -eq 1 ]; then
  echo "(see CLAUDE.md / AGENTS.md; fix before committing)"
fi
exit 0
