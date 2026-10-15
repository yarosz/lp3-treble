#!/usr/bin/env bash
# GSI picture-message loop (checklist: MMS out, MMS in) through AOSP Messaging's own picker (adb share intents crash
# it): compose to the line's own number, attach the newest image from the photo picker, caption, send; then wait for
# the received copy (wait-mms.sh). Sends a real MMS.
# Needs an image in MediaStore (e.g. adb push one to /sdcard/Pictures/). Usage: gsi-mms-image.sh "<caption>" [wait s]
# Env: ANDROID_SERIAL, LP3_NUMBER (digits).
set -uo pipefail
S=${ANDROID_SERIAL:?set ANDROID_SERIAL}; own=${LP3_NUMBER:?set LP3_NUMBER}; cap=${1:-mms test}
here=$(cd "$(dirname "$0")" && pwd)
a() { adb -s "$S" shell "$@" </dev/null | tr -d '\r'; }
ui() { "$here/../../tools/gsi-ui.sh" "$@"; }
last=$(a content query --uri content://mms --projection _id | sed -n 's/.*_id=\([0-9]*\).*/\1/p' | sort -n | tail -1)
a input keyevent 224; a wm dismiss-keyguard; sleep 1
a am start -a android.intent.action.SENDTO -d "sms:$own" >/dev/null; sleep 3
ui tap 'id/attach_media_button' && sleep 2 &&
ui tap 'content-desc="Choose images from this device"' && sleep 2 &&
ui tap 'text="Choose images from this device"' && sleep 4 &&
ui tap 'id/icon_thumbnail' && sleep 2 &&
ui tap 'text="Add \(1\)"' && sleep 3 &&
ui tap 'id/compose_message_text' || { echo "picker flow failed"; exit 2; }
a input text "$(printf '%s' "$cap" | sed 's/ /%s/g')"
ui ids 80 | grep -q 'text="MMS"' || { echo "compose is not in MMS mode"; exit 3; }
ui tap 'id/send_message_button' >/dev/null; echo "$(date +%T) sent (MMS rows before: up to _id ${last:-0})"
"$here/wait-mms.sh" "${2:-180}" "${last:-0}"
