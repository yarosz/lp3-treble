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

# This file holds the patterns themselves. Cargo.lock is generated: crate names, versions and sha256 checksums,
# whose hex has long digit runs.
exclude=(':!scripts/privacy-scan.sh' ':!metamodule/Cargo.lock')

status=0
if [ $# -eq 0 ]; then
  git grep -nIE "$pattern" -- . "${exclude[@]}" && status=1
else
  for rev in "$@"; do
    git grep -nIE "$pattern" "$rev" -- . "${exclude[@]}" && status=1
  done
fi

if [ $status -ne 0 ]; then
  echo "privacy-scan: identifier-shaped text found above; scrub it before pushing." >&2
fi
exit $status
