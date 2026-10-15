#!/usr/bin/env bash
# GSI incoming SMS with the screen off or in deep doze (checklist: SMS in, screen off): put the phone in the given
# state, text it from Google Voice (gv/gv-text-lp3.sh), and wait for the SMS row.
#   screenoff: screen off (KEYCODE_SLEEP), 30 s settle
#   doze:      screen off, then `dumpsys deviceidle force-idle` (deep doze), checked before sending
# Usage: mt-sms-test.sh <screenoff|doze> "<text>" [wait seconds, default 180]   Text: letters, digits, spaces only.
# Env: ANDROID_SERIAL, LP3_NUMBER; Google Voice set up as in README.md.
# Prints RECEIVED/NOT RECEIVED and the matching IMS log lines. Space tests a few minutes apart (SMSC backoff).
set -uo pipefail
mode=$1; text=$2; t=${3:-180}; S=${ANDROID_SERIAL:?set ANDROID_SERIAL}; here=$(cd "$(dirname "$0")" && pwd)
a() { adb -s "$S" "$@" </dev/null; }
a shell input keyevent 223
sleep 30
if [ "$mode" = doze ]; then
  a shell dumpsys deviceidle force-idle
  a shell dumpsys deviceidle get deep | sed 's/^/deep idle: /'
fi
a shell dumpsys power | grep -m1 'mWakefulness=' | sed 's/^ */power: /'
tab=$("$here/gv/gv-tab.sh")
"$here/gv/gv-text-lp3.sh" "$tab" "$text" | tail -1
echo "sent at $(date +%T)"
for _ in $(seq 1 $((t / 3))); do
  # One string: adb joins the args and the phone's shell splits them again.
  if a shell "content query --uri content://sms --projection _id --where \"type=1 AND body='$text'\"" | grep -q Row; then
    echo "RECEIVED at $(date +%T): $text"
    a shell dumpsys power | grep -m1 'mWakefulness=' | sed 's/^ */power at receipt: /'
    [ "$mode" = doze ] && a shell dumpsys deviceidle get deep | sed 's/^/deep idle at receipt: /'
    a logcat -d | grep -E "onIncomingSms\(|onSmsReceived" | tail -2 | cut -c1-160
    exit 0
  fi
  sleep 3
done
echo "NOT RECEIVED in ${t}s: $text"
exit 1
