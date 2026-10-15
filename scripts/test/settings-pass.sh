#!/usr/bin/env bash
# GSI Settings pass: open each main Settings screen, dump its text (two screens' worth, one scroll) with
# tools/ui-dump.sh, plus screenshots. Read-only. Output may hold personal data (IMEI, number): keep it private,
# never publish it raw.
# Usage: settings-pass.sh <serial> <out dir>
set -uo pipefail
s=${1:?serial}; out=${2:?out dir}; tools=$(cd "$(dirname "$0")/../../tools" && pwd)
mkdir -p "$out"
# Swipe from 3/4 to 1/4 of the screen height (the LP3 panel is 1080x1240); wm size's last line wins (Override).
read -r w h < <(adb -s "$s" shell wm size </dev/null | tr -d '\r' | sed -n 's/.*: *\([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)
[ -n "${h:-}" ] || { echo "wm size gave no size"; exit 1; }
screens="
about:android.settings.DEVICE_INFO_SETTINGS
battery:android.intent.action.POWER_USAGE_SUMMARY
display:android.settings.DISPLAY_SETTINGS
sound:android.settings.SOUND_SETTINGS
network:android.settings.WIRELESS_SETTINGS
sim:android.settings.NETWORK_OPERATOR_SETTINGS
storage:android.settings.INTERNAL_STORAGE_SETTINGS
location:android.settings.LOCATION_SOURCE_SETTINGS
security:android.settings.SECURITY_SETTINGS
system:android.settings.SYSTEM_UPDATE_SETTINGS
date:android.settings.DATE_SETTINGS
accessibility:android.settings.ACCESSIBILITY_SETTINGS
buttons:org.lineageos.lineageparts.BUTTON_SETTINGS
"
for entry in $screens; do
  name=${entry%%:*}; action=${entry#*:}
  adb -s "$s" shell am start -a "$action" </dev/null >/dev/null 2>&1
  sleep 2
  { echo "== $name ($action)"; "$tools/ui-dump.sh" "$s"; } >"$out/$name.txt" 2>&1
  adb -s "$s" exec-out screencap -p >"$out/$name-1.png" </dev/null
  adb -s "$s" shell input swipe $((w / 2)) $((h * 3 / 4)) $((w / 2)) $((h / 4)) 300 </dev/null
  sleep 1
  { echo "== $name (scrolled)"; "$tools/ui-dump.sh" "$s"; } >>"$out/$name.txt" 2>&1
  adb -s "$s" exec-out screencap -p >"$out/$name-2.png" </dev/null
  adb -s "$s" shell input keyevent 3 </dev/null
done
echo "done: $out"
