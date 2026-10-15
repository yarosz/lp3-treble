#!/usr/bin/env bash
# GSI MMS loop (checklist: MMS out, MMS in, the group-text form): a group message to the line's own number plus a
# second number, which AOSP Messaging sends as one MMS (group MMS on). The line receives its own copy back as an
# incoming MMS (WAP push + MMSC download). Sends a real MMS.
# Usage: gsi-self-mms.sh [serial] [body: letters, digits, spaces]   Env: LP3_NUMBER, PEER_NUMBER (digits); serial default $ANDROID_SERIAL.
# Not an image: sharing an image into Messaging from adb (ACTION_SEND with a MediaStore URI) crashes Messaging when it
# forwards the URI grant to ConversationActivity (SecurityException in UriGrantsManagerService), even after
# `pm grant ... READ_MEDIA_IMAGES`; use gsi-mms-image.sh. A ~1 KB text didn't convert to MMS either (went as
# multipart SMS).
set -uo pipefail
S=${1:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}; body=${2:-group mms test}
[[ $body =~ ^[A-Za-z0-9\ ]+$ ]] || { echo "body: letters, digits and spaces only"; exit 2; }
own=${LP3_NUMBER:?set LP3_NUMBER}; peer=${PEER_NUMBER:?set PEER_NUMBER}
a() { adb -s "$S" shell "$@" </dev/null | tr -d '\r'; }
mms_count() { a content query --uri content://mms --projection _id:m_type | grep -c 'm_type=132'; }
before=$(mms_count)
a input keyevent 224; a wm dismiss-keyguard; sleep 1
a am start -a android.intent.action.SENDTO -d "smsto:$own,$peer" --es sms_body "'$body'" >/dev/null
sleep 4
xml=$(adb -s "$S" exec-out uiautomator dump /dev/tty </dev/null 2>/dev/null | tr '>' '\n')
grep -qiE 'text="MMS"|content-desc="[^"]*MMS' <<<"$xml" && echo "compose shows MMS"
b=$(grep 'id/send_message_button' <<<"$xml" | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)
[ -n "$b" ] || { echo "send button not found"; grep -oE 'resource-id="[^"]+"' <<<"$xml" | sort -u | head -30; exit 2; }
read -r x1 y1 x2 y2 < <(printf '%s\n' "$b" | tr -c '0-9\n' ' ')
a input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 ))
echo "$(date +%T) SENT; received MMS before: $before"
for _ in $(seq 1 60); do
  n=$(mms_count)
  [ "$n" -gt "$before" ] && { echo "$(date +%T) RECEIVED MMS"; a content query --uri content://mms --projection _id:msg_box:m_type:st:resp_st:sub; exit 0; }
  sleep 3
done
echo "$(date +%T) no new received MMS within 3 min"; a content query --uri content://mms --projection _id:msg_box:m_type:st:resp_st
exit 1
