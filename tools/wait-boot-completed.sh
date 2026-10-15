#!/usr/bin/env bash
# Wait (up to 4 min) for sys.boot_completed=1; print the time. Read-only.
# Usage: wait-boot-completed.sh [serial]   (default: $ANDROID_SERIAL)
S=${1:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}
for i in $(seq 1 80); do
  [ "$(adb -s "$S" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && { echo "$(date +%H:%M:%S) boot_completed"; exit 0; }
  sleep 3
done
echo "$(date +%H:%M:%S) NOT boot_completed"; exit 1
