#!/usr/bin/env bash
# After a fresh DSU install (phone on LightOS): first GSI boot, LTE + phh's IMS APK, mark the GSI provisioned, then
# a second boot (the first boot never binds the CAF ImsService), and wait for service and IMS registration.
# Usage: gsi-fresh-boot.sh <phh IMS apk> [serial]   (default serial: $ANDROID_SERIAL)
# Writes: the GSI's network-type setting, the IMS app install, device_provisioned / user_setup_complete.
set -euo pipefail
apk=${1:?phh IMS apk}; S=${2:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}; here=$(cd "$(dirname "$0")" && pwd)
"$here/gsi-reboot.sh" "$S"
"$here/gsi-ims-setup.sh" "$apk" "$S"
adb -s "$S" shell "settings put global device_provisioned 1; settings put secure user_setup_complete 1" </dev/null
"$here/gsi-reboot.sh" "$S"
ANDROID_SERIAL=$S "$here/wait-in-service.sh" 120
"$here/wait-ims-reg.sh" "$S" || { echo "IMS did not register"; exit 1; }
