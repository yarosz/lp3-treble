#!/usr/bin/env bash
# Re-verify a partition-dump.sh output dir: every manifest row must be OK and its <name>.img.zst must decompress to
# the device sha256 in manifest.tsv; super, vbmeta_a and boot_a (the full flash and its rollback) must be there.
# Read-only, no phone needed. Usage: verify-dump.sh <dump dir>   Exit 0 = all OK.
set -uo pipefail
d=${1:?dump dir}; man="$d/manifest.tsv"; bad=0; rows=0; seen=" "
[ -s "$man" ] || { echo "BAD: no manifest at $man"; exit 1; }
while IFS=$'\t' read -r n st b g dsha hsha; do
  [ -n "$n" ] || continue
  rows=$((rows + 1)); seen="$seen$n "
  if [ "$st" != OK ]; then echo "BAD $n (manifest status: $st)"; bad=1; continue; fi
  a=$(zstd -dc "$d/$n.img.zst" | shasum -a 256 | cut -d' ' -f1)
  if [ -n "$dsha" ] && [ "$a" = "$dsha" ]; then echo "OK $n"; else echo "BAD $n"; bad=1; fi
done < "$man"
[ "$rows" -gt 0 ] || { echo "BAD: manifest has no rows"; bad=1; }
for p in super vbmeta_a boot_a; do
  case "$seen" in *" $p "*) ;; *) echo "MISSING $p (needed for the full flash and rollback)"; bad=1;; esac
done
exit $bad
