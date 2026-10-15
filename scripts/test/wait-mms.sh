#!/usr/bin/env bash
# Wait (default 180 s) for MMS rows: prints the MMS table when a received MMS (m_type 132) appears. Read-only.
# msg_box 1 = inbox, 2 = sent, 4 = outbox, 5 = failed. Usage: wait-mms.sh [secs] [after_id]   Env: ANDROID_SERIAL.
# after_id: only rows with a larger _id count (pass the newest _id from before the send).
set -uo pipefail
S=${ANDROID_SERIAL:?set ANDROID_SERIAL}; t=${1:-180}; after=${2:-0}
q() { adb -s "$S" shell content query --uri content://mms --projection _id:msg_box:m_type:st:resp_st:ct_t --where "_id\\>$after" </dev/null | tr -d '\r'; }
for _ in $(seq 1 $(( t / 3 ))); do
  rows=$(q); grep -q 'm_type=132' <<<"$rows" && { echo "$(date +%T) RECEIVED MMS"; echo "$rows"; exit 0; }
  sleep 3
done
echo "$(date +%T) no received MMS within ${t}s"; echo "$rows"
exit 1
