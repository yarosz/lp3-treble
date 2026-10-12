#!/usr/bin/env bash
# Gzip a raw system image for DSU and print the install command. Does not run adb.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: pack-dsu.sh <system.img> <out.gz>

Writes <out.gz> (DSU accepts .gz or .zip only, not .xz) and prints the adb commands to
install it. Nothing is sent to a device. Env: USERDATA_SIZE bytes (default 8589934592 = 8 GiB).
USAGE
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac
if [ $# -ne 2 ]; then usage >&2; exit 64; fi
in=$1 out=$2
[ -f "$in" ] || { echo "error: image not found: $in" >&2; exit 64; }
case "$out" in *.gz) ;; *) echo "error: output must end in .gz" >&2; exit 64 ;; esac
[ ! -e "$out" ] || { echo "error: output exists, refusing to overwrite: $out" >&2; exit 64; }

size=$(wc -c <"$in" | tr -d ' ')
userdata=${USERDATA_SIZE:-8589934592}

gzip -c "$in" >"$out"
echo "wrote $out ($(wc -c <"$out" | tr -d ' ') bytes; image is $size bytes uncompressed)"
cat <<EOF

Text only, nothing was run. Phone needs free space for the system image plus userdata.

adb push $out /storage/emulated/0/Download/
adb shell am start-activity -n com.android.dynsystem/com.android.dynsystem.VerificationActivity \\
  -a android.os.image.action.START_INSTALL \\
  -d file:///storage/emulated/0/Download/$(basename "$out") \\
  --el KEY_SYSTEM_SIZE $size --el KEY_USERDATA_SIZE $userdata
EOF
