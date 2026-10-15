#!/usr/bin/env bash
# Wait (up to 3 min) for phh's IMS app (QImsService) to log an IMS registration in the GSI; then print the
# capability lines. Read-only. Usage: wait-ims-reg.sh [serial]   (default: $ANDROID_SERIAL)   Exit 1 on timeout.
S=${1:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}
rc=1
for i in $(seq 1 60); do
  adb -s "$S" logcat -d </dev/null 2>/dev/null | grep -q "VOLTE ims registered" && { rc=0; break; }
  sleep 3
done
adb -s "$S" logcat -b radio -d </dev/null | grep -E "handleFeatureCapabilityChanged|setImsRegistrationState" | tail -4 | cut -c1-260
[ $rc = 0 ] || echo "timeout: no IMS registration in 3 min"
exit $rc
