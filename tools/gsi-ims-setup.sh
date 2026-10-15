#!/usr/bin/env bash
# After a fresh DSU GSI boot: allow LTE/NR on SIM slot 1 (gsi-set-lte.sh) and install phh's CAF IMS APK, which is
# what the "Install IMS APK" button in phh's Treble settings does. Download the APK yourself from phh
# (treble.phh.me); this repo does not ship it.
# Usage: gsi-ims-setup.sh <phh IMS apk> [serial]   (default serial: $ANDROID_SERIAL)
# Writes: the network-type setting and the app install (skipped when org.codeaurora.ims is already installed).
set -euo pipefail
apk=${1:?phh IMS apk}; S=${2:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}; here=$(cd "$(dirname "$0")" && pwd)
[ -f "$apk" ] || { echo "no such file: $apk" >&2; exit 64; }
"$here/wait-boot-completed.sh" "$S"
adb -s "$S" shell < "$here/gsi-set-lte.sh"
adb -s "$S" shell pm list packages org.codeaurora.ims </dev/null | grep -q . || adb -s "$S" install "$apk"
