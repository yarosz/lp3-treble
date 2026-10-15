#!/usr/bin/env bash
# Poll (up to 10 min) until the DSU install finishes (gsi_tool status: installed) or times out; print the final
# state. Read-only. Usage: wait-dsu-ready.sh [serial]   (default: $ANDROID_SERIAL)
S=${1:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}
for i in $(seq 1 120); do
  st=$(adb -s "$S" shell gsi_tool status </dev/null 2>&1 | tr '\n' ' ')
  case "$st" in *installed*) echo "READY: $st"; exit 0;; esac
  if [ $((i % 10)) -eq 0 ]; then echo "t=$((i*5))s $st"; fi
  sleep 5
done
echo "TIMEOUT: $st"; exit 1
