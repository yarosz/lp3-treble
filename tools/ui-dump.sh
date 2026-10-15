#!/usr/bin/env bash
# Dump the phone's current UI hierarchy; print one line per node that has text or a content-desc, with its centre.
# Usage: ui-dump.sh <serial>   (read-only; output may show personal data, keep it local)
# LightOS draws some screens (its keyboard, for one) in-app, invisible to uiautomator: take a screenshot there.
set -uo pipefail
s=${1:?serial}
adb -s "$s" shell uiautomator dump /sdcard/lp3-ui.xml </dev/null >/dev/null 2>&1
xml=$(adb -s "$s" shell cat /sdcard/lp3-ui.xml </dev/null 2>/dev/null)
adb -s "$s" shell rm -f /sdcard/lp3-ui.xml </dev/null
case "$xml" in *"<hierarchy"*) ;; *) echo "empty UI dump (screen off, secure window or uiautomator busy): take a screenshot"; exit 1;; esac
printf '%s' "$xml" | python3 -I -c '
import sys, re, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
for n in root.iter("node"):
    t, d, c = n.get("text", ""), n.get("content-desc", ""), n.get("clickable") == "true"
    if not (t or d): continue
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", n.get("bounds")))
    print(f"({(x1+x2)//2},{(y1+y2)//2}) click={c} text={t!r} desc={d!r}")
'
