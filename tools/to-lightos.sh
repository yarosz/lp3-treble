#!/usr/bin/env bash
# Leave the DSU GSI for stock LightOS (a one-shot DSU boot falls back on the next reboot) and wait for boot.
# No-op when already on LightOS. Usage: to-lightos.sh [serial]   (default: $ANDROID_SERIAL)
S=${1:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}; here=$(cd "$(dirname "$0")" && pwd)
in_gsi() { [ -n "$(adb -s "$S" shell getprop ro.lineage.version </dev/null | tr -d '\r')" ]; }
in_gsi || { echo "already on LightOS"; exit 0; }
adb -s "$S" reboot </dev/null
adb -s "$S" wait-for-disconnect 2>/dev/null || true
adb -s "$S" wait-for-device
"$here/wait-boot-completed.sh" "$S"
in_gsi && { echo "still in GSI after reboot"; exit 1; }
echo "on LightOS"
