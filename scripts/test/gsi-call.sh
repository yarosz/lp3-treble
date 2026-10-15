#!/usr/bin/env bash
# GSI voice test (checklist: call out, call in).
#   out <digits|peer|self> [secs]  place a call, wait for ACTIVE, hold secs (default 15), hang up
#   in [secs]                      wait (up to 3 min) for a RINGING call, answer it, hold, hang up
# Then print the newest call-log row (number column omitted; features 64 = VoLTE) and the telecom call state.
# Usage: gsi-call.sh out|in ...   Env: ANDROID_SERIAL; PEER_NUMBER for "peer", LP3_NUMBER for "self" (digits).
# Places or answers a real call; writes nothing else. Exit 1 if RINGING or ACTIVE timed out.
set -uo pipefail
S=${ANDROID_SERIAL:?set ANDROID_SERIAL}
usage() { echo "usage: gsi-call.sh out <digits|peer|self> [secs] | in [secs]"; exit 2; }
sh_() { adb -s "$S" shell "$@" </dev/null; }
state() { sh_ dumpsys telecom | grep -oE 'state: ?[A-Z_]+|state=[A-Z_]+' | head -1; }
wait_for() { # pattern timeout_s
  for _ in $(seq 1 "$2"); do st=$(state); case "$st" in *$1*) echo "$(date +%T) $st"; return 0;; esac; sleep 1; done
  echo "$(date +%T) timeout waiting for $1 (last: ${st:-none})"; return 1
}
mode=${1:-}; [ $# -gt 0 ] && shift
case "$mode" in out) [ $# -ge 1 ] || usage;; in) ;; *) usage;; esac
sh_ input keyevent 224; sh_ wm dismiss-keyguard; sleep 1
rc=0; up=0
if [ "$mode" = out ]; then
  case $1 in peer) num=${PEER_NUMBER:?set PEER_NUMBER};; self) num=${LP3_NUMBER:?set LP3_NUMBER};; *) num=$1;; esac
  hold=${2:-15}
  sh_ am start -a android.intent.action.CALL -d "tel:$num" >/dev/null
  up=1  # a placed call is up (dialing) even if it never goes ACTIVE
  if wait_for ACTIVE 60; then sleep "$hold"; else rc=1; fi
else
  hold=${1:-15}
  if wait_for RINGING 180; then
    up=1; sleep 2; sh_ input keyevent 5
    if wait_for ACTIVE 20; then sleep "$hold"; else rc=1; fi
  else rc=1; fi
fi
if [ $up = 1 ]; then sh_ input keyevent 6; sleep 3; fi
echo "after hangup: $(state || true)"; sh_ dumpsys telephony.registry | grep -m1 mCallState
sh_ content query --uri content://call_log/calls --projection _id:type:duration:features:date --sort "'_id DESC'" | head -1
exit $rc
