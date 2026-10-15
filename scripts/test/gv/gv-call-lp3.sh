#!/usr/bin/env bash
# Incoming-call test (checklist: call in): the GSI side waits for RINGING and answers (gsi-call.sh in), while Google
# Voice calls the LP3 and hangs up after at most <secs> (default 60). Places a real call.
# Usage: gv-call-lp3.sh [secs]   (phone booted in the GSI, IMS registered)   Env: ANDROID_SERIAL, LP3_NUMBER.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
num=${LP3_NUMBER:?set LP3_NUMBER}
tab=$("$here/gv-tab.sh")
"$here/../gsi-call.sh" in 15 &
phone=$!
sleep 3
node --no-warnings --experimental-websocket "$here/gv-call.js" "$tab" "$num" "${1:-60}"
wait "$phone"
