#!/usr/bin/env bash
# Boot the installed DSU GSI again. A one-shot DSU boot falls back to LightOS on the next reboot, so: if in the
# GSI, reboot to LightOS first; then arm the one-shot boot and reboot; wait for boot_completed.
# Usage: gsi-reboot.sh [serial]   (default: $ANDROID_SERIAL)   Reboots the phone; writes nothing else.
set -euo pipefail
S=${1:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}; here=$(cd "$(dirname "$0")" && pwd)
in_gsi() { [ -n "$(adb -s "$S" shell getprop ro.lineage.version </dev/null | tr -d '\r')" ]; }
up_since() { adb -s "$S" shell cat /proc/uptime </dev/null | cut -d. -f1; }
wait_reboot() { # wait for adb to drop, come back, and finish booting
  adb -s "$S" wait-for-disconnect 2>/dev/null || true
  adb -s "$S" wait-for-device
  "$here/wait-boot-completed.sh" "$S"
}
if in_gsi; then adb -s "$S" reboot </dev/null; wait_reboot; fi
in_gsi && { echo "still in GSI after reboot"; exit 1; }
adb -s "$S" shell < "$here/dsu-oneshot.sh"
adb -s "$S" reboot </dev/null; wait_reboot
in_gsi && echo "GSI up, uptime $(up_since)s" || { echo "NOT in GSI (fell back to LightOS?)"; exit 1; }
