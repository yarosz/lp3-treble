#!/usr/bin/env bash
# GSI UI helper over uiautomator. Phone numbers and long digit runs in the output are masked.
#   gsi-ui.sh ids [n]             resource-ids, texts and content-descs on screen (first n, default 60); read-only
#   gsi-ui.sh tap <regex>         tap the centre of the first node whose line matches <regex>
#   gsi-ui.sh focus               the focused window; read-only
# Env: ANDROID_SERIAL = the phone's adb serial. Meant for the GSI; it does not guard against driving LightOS.
set -uo pipefail
S=${ANDROID_SERIAL:?set ANDROID_SERIAL}
dump() { adb -s "$S" exec-out uiautomator dump /dev/tty </dev/null 2>/dev/null | tr '>' '\n'; }
mask() { sed -E 's/\(?[0-9]{3}\)? ?[0-9]{3}-[0-9]{4}/<num>/g; s/[0-9]{7,}/<n>/g'; }
usage() { echo "usage: gsi-ui.sh ids [n] | tap <regex> | focus"; exit 2; }
case ${1:-} in
  ids) dump | grep -oE '(resource-id|text|content-desc)="[^"]+"' | mask | awk '!s[$0]++' | head -${2:-60} ;;
  tap)
    [ -n "${2:-}" ] || usage
    b=$(dump | grep -E "$2" | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)
    [ -n "$b" ] || { echo "no node matches: $2"; exit 1; }
    read -r x1 y1 x2 y2 < <(printf '%s\n' "$b" | tr -c '0-9\n' ' ')
    adb -s "$S" shell input tap $(( (x1+x2)/2 )) $(( (y1+y2)/2 )) </dev/null
    echo "tapped $(( (x1+x2)/2 )),$(( (y1+y2)/2 ))" ;;
  focus) adb -s "$S" shell dumpsys window displays </dev/null | grep -m1 mCurrentFocus | mask ;;
  *) usage ;;
esac
