#!/usr/bin/env bash
# macOS only. Mount the encrypted backup bundle that backup-encrypt.sh made at /Volumes/LP3-backup, for example to
# read a partition dump for rollback.sh. The passphrase comes from a hidden macOS dialog and goes straight to hdiutil
# on stdin: never a command line, log or transcript.
# Usage: backup-attach.sh <bundle>   Detach afterwards: hdiutil detach /Volumes/LP3-backup
set -euo pipefail
bundle=${1:?bundle}
if [ -d /Volumes/LP3-backup ]; then
  # hdiutil info: one block per image, "image-path : <path>" first, its mount points after it.
  img=$(hdiutil info | awk -F' : ' '/^image-path/ {p=$2} /\/Volumes\/LP3-backup$/ {print p; exit}')
  [ -n "$img" ] && [ "$(cd "$img" && pwd -P)" = "$(cd "$bundle" && pwd -P)" ] \
    && { echo "already mounted: /Volumes/LP3-backup"; exit 0; }
  echo "/Volumes/LP3-backup is another volume (${img:-unknown}): detach it first" >&2; exit 1
fi
osascript -e 'tell application "System Events" to activate' >/dev/null 2>&1 || true
p=$(osascript -e 'text returned of (display dialog "Passphrase for the LP3 backup image:" default answer "" with hidden answer buttons {"Cancel","OK"} default button "OK" with title "LP3 backup" giving up after 900)')
[ -n "$p" ] || { echo "no passphrase" >&2; exit 1; }
printf '%s' "$p" | hdiutil attach -stdinpass -nobrowse "$bundle" | awk -F'\t' '/\/Volumes\// {print "mounted", $NF}'
