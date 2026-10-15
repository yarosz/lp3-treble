#!/usr/bin/env bash
# Re-verify a partition-dump.sh output dir: each <name>.img.zst must decompress to the device sha256 in
# manifest.tsv. Read-only, no phone needed. Usage: verify-dump.sh <dump dir>   Exit 0 = all OK.
set -uo pipefail
d=${1:?dump dir}; bad=0
while IFS=$'\t' read -r n st b g dsha hsha; do
  a=$(zstd -dc "$d/$n.img.zst" | shasum -a 256 | cut -d' ' -f1)
  if [ "$a" = "$dsha" ]; then echo "OK $n"; else echo "BAD $n"; bad=1; fi
done < "$d/manifest.tsv"
exit $bad
