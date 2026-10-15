#!/usr/bin/env bash
# Wait (default 120 s) until a phone slot reports voice IN_SERVICE; print the operator and radio tech. Read-only.
# Usage: wait-in-service.sh [secs]   Env: ANDROID_SERIAL = the phone's adb serial.
S=${ANDROID_SERIAL:?set ANDROID_SERIAL}; t=${1:-120}
for _ in $(seq 1 $((t/3))); do
  line=$(adb -s "$S" shell dumpsys telephony.registry </dev/null 2>/dev/null | grep mServiceState | grep -m1 "mVoiceRegState=0(IN_SERVICE)")
  [ -n "$line" ] && { echo "$(date +%T) $(echo "$line" | grep -oE 'mOperatorAlphaLong=[^,]*|getRilVoiceRadioTechnology=[^,]*' | tr '\n' ' ')"; exit 0; }
  sleep 3
done
echo "$(date +%T) NOT in service after ${t}s"; exit 1
