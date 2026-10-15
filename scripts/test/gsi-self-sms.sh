#!/usr/bin/env bash
# GSI SMS out (checklist: SMS out): open AOSP Messaging's compose screen to a number with a body, then press the send
# button found by uiautomator. Sends a real SMS.
# Usage: gsi-self-sms.sh [serial] [body] [self|peer]
#   self (default) texts the line's own number (LP3_NUMBER); some networks don't loop that back, use peer there
#   peer texts PEER_NUMBER. Serial default: $ANDROID_SERIAL.
set -euo pipefail
S=${1:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}; body=${2:-lp3 treble self test}
case ${3:-self} in peer) num=${PEER_NUMBER:?set PEER_NUMBER};; *) num=${LP3_NUMBER:?set LP3_NUMBER};; esac
[ ${#num} -ge 10 ] || { echo "number too short"; exit 1; }
adb -s "$S" shell input keyevent 224 </dev/null
adb -s "$S" shell wm dismiss-keyguard </dev/null || true; sleep 1
adb -s "$S" shell am start -a android.intent.action.SENDTO -d "sms:$num" --es sms_body "'$body'" </dev/null >/dev/null
sleep 3
xml=$(adb -s "$S" exec-out uiautomator dump /dev/tty </dev/null 2>/dev/null || true)
b=$(printf '%s' "$xml" | tr '>' '\n' | grep 'id/send_message_button' | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1 || true)
[ -n "$b" ] || { echo "send button not found"; printf '%s' "$xml" | tr '>' '\n' | grep -oE 'resource-id="[^"]+"' | sort -u | head -30; exit 2; }
read -r x1 y1 x2 y2 < <(printf '%s\n' "$b" | tr -c '0-9\n' ' ')
adb -s "$S" shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 )) </dev/null
echo "SENT tap at $(( (x1+x2)/2 )),$(( (y1+y2)/2 ))"
