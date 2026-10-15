#!/usr/bin/env bash
# Print the CDP tab id of the Google Voice tab whose URL contains the LP3's number, or of any voice.google.com tab
# when none does. Exit 1 if there is no GV tab. Read-only. Needs curl and jq.
# Env: LP3_NUMBER (digits). The browser must listen for CDP on 127.0.0.1:9222 (see scripts/test/README.md).
set -euo pipefail
num=${LP3_NUMBER:?set LP3_NUMBER}
tabs=$(curl -s http://127.0.0.1:9222/json)
id=$(echo "$tabs" | jq -r --arg n "$num" '[.[] | select(.type=="page" and (.url|contains("voice.google.com")))] as $v
  | (([$v[] | select(.url|contains($n))] + $v)[0].id) // empty')
[ -n "$id" ] || { echo "no Google Voice tab in the browser" >&2; exit 1; }
echo "$id"
