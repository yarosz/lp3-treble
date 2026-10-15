#!/usr/bin/env bash
# Stream partitions from a temp-rooted LP3 to this computer, zstd-compressed, and verify each against a device-side
# sha256 and the block device size. Writes <outdir>/<name>.img.zst and <outdir>/manifest.tsv (name, OK|BAD, bytes,
# bytes read back, device sha256, host sha256), the format verify-dump.sh, fullflash.sh and rollback.sh read.
# Read-only on the phone. Needs: one-boot root (temp-root-boot.sh) with su granted to Shell, zstd on the host.
# Usage: partition-dump.sh <serial> <list file> <outdir>
#   list file: one "name /dev/block/by-name/X bytes" per line, e.g. super and vbmeta_a for the full flash and boot_a
#   for its rollback (sizes: blockdev --getsize64 as root).
# Resumable: partitions already marked OK in the manifest are skipped. Uses BSD sed (macOS).
# The output holds Light's software and, for some partitions, device identifiers: never publish or share it.
set -uo pipefail
s=${1:?serial}; list=${2:?list}; out=${3:?outdir}
mkdir -p "$out"; man="$out/manifest.tsv"; touch "$man"
ok=0; bad=0
while read -r name dev bytes; do
  [ -n "$name" ] || continue
  if grep -q "^$name	OK	" "$man"; then ok=$((ok + 1)); continue; fi
  dsha=$(adb -s "$s" exec-out "su -c 'sha256sum $dev'" </dev/null | awk '{print $1}')
  # Save first, then hash and size what is on disk, so OK describes the saved file.
  adb -s "$s" exec-out "su -c 'dd if=$dev bs=4194304 2>/dev/null'" </dev/null | zstd -q -T0 -3 -f -o "$out/$name.img.zst"
  hsha=$(zstd -dc "$out/$name.img.zst" | shasum -a 256 | awk '{print $1}')
  got=$(zstd -dc "$out/$name.img.zst" | wc -c | tr -d ' ')
  if [ -n "$dsha" ] && [ "$dsha" = "$hsha" ] && [ "$got" = "$bytes" ]; then st=OK; ok=$((ok + 1)); else st=BAD; bad=$((bad + 1)); fi
  sed -i '' "/^$name	/d" "$man"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$st" "$bytes" "$got" "$dsha" "$hsha" >> "$man"
  echo "$st $name $bytes"
done < "$list"
echo "done: ok=$ok bad=$bad $(date)"
