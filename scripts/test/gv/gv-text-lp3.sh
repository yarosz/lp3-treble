#!/usr/bin/env bash
# Send a Google Voice text to the LP3 (sends a real SMS).
# Usage: gv-text-lp3.sh <tabId> <text>   (tab id from gv-tab.sh; open a GV tab first with
#   curl -X PUT 'http://127.0.0.1:9222/json/new?https://voice.google.com/u/0/')
# Env: LP3_NUMBER (digits).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
num=${LP3_NUMBER:?set LP3_NUMBER}
node --no-warnings --experimental-websocket "$here/gv.js" "$1" send "$num" "$2"
