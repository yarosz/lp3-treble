#!/usr/bin/env bash
# Privacy scan for lp3-treble. Rejects identifiers that must never be published:
# 14-20 digit runs (IMEI, IMSI, ICCID, EID), phone numbers, email addresses, MAC addresses.
# Usage: privacy-scan.sh <rev>...   scans each revision's tree
#        privacy-scan.sh            scans the tracked files in the working tree
set -euo pipefail

digits='(^|[^0-9])[0-9]{14,20}([^0-9]|$)'
phone='(\+?1[ .-]?)?\(?[2-9][0-9]{2}\)?[ .-][0-9]{3}[ .-][0-9]{4}([^0-9]|$)'
email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
mac='([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'
pattern="($digits)|($phone)|($email)|($mac)"

# This file holds the patterns themselves.
exclude=(':!scripts/privacy-scan.sh')
# Cargo.lock's sha256 checksum lines are generated hex with long digit runs: drop only those lines.
lockfile_checksum=':checksum = "[0-9a-f]{64}"$'

# scan [rev]: matching lines, minus Cargo.lock checksum lines. Fails when anything is left.
scan() {
  local hits
  hits=$(git grep -nIE "$pattern" "$@" -- . "${exclude[@]}" | grep -vE "Cargo\.lock:[0-9]+$lockfile_checksum" || true)
  [ -z "$hits" ] && return 0
  printf '%s\n' "$hits"
  return 1
}

status=0
if [ $# -eq 0 ]; then
  scan || status=1
else
  for rev in "$@"; do
    scan "$rev" || status=1
  done
fi

if [ $status -ne 0 ]; then
  echo "privacy-scan: identifier-shaped text found above; scrub it before pushing." >&2
fi
exit $status
