#!/usr/bin/env bash
# One-boot root on stock LightOS 00WW_1_440000: `fastboot boot` the rooted resukisu-boot.img from vandamd/light-guide's
# lightos-resukisu-susfs-00WW_1_440000-preview1 release. Nothing is written to the phone; the next normal reboot
# returns to the stock kernel. Then install the ReSukiSU manager app from the same release and grant Superuser to
# Shell in it (needed by partition-dump.sh).
# Usage: temp-root-boot.sh <resukisu-boot.img> [serial]   (default serial: $ANDROID_SERIAL)
# Refuses an image whose sha256 differs from the tested one, and any firmware but 00WW_1_440000.
set -uo pipefail
img=${1:?resukisu-boot.img}; S=${2:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}
[ "$(shasum -a 256 "$img" | cut -d' ' -f1)" = 820e91e882af25a9174dd23a4caea70412fdf97159f951ab0df9b2e531760fe9 ] || { echo "boot image hash mismatch"; exit 1; }
[ "$(adb -s "$S" shell getprop ro.vendor.build.version.incremental </dev/null | tr -d '\r')" = 00WW_1_440000 ] || { echo "firmware mismatch"; exit 1; }
adb -s "$S" reboot bootloader
for i in $(seq 1 40); do fastboot devices | grep -q "$S" && break; sleep 2; done
fastboot devices | grep -q "$S" || { echo "no fastboot device"; exit 2; }
fastboot -s "$S" boot "$img" || { echo "fastboot boot FAILED; recover with: fastboot -s $S reboot"; exit 3; }
for i in $(seq 1 90); do
  [ "$(adb -s "$S" shell getprop sys.boot_completed </dev/null 2>/dev/null | tr -d '\r')" = 1 ] && break; sleep 3
done
k=$(adb -s "$S" shell uname -r </dev/null | tr -d '\r')
echo "kernel=$k display=$(adb -s "$S" shell getprop ro.build.display.id </dev/null | tr -d '\r')"
case "$k" in *LP3*) echo "TEMP ROOT KERNEL UP";; *) echo "NOT the ReSukiSU kernel (boot fell back?)"; exit 4;; esac
