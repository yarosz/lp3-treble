#!/usr/bin/env bash
# Wipe the current DSU image, push a patched .img.gz to the phone and start the DSU install. Run on stock LightOS.
# Usage: dsu-install.sh <serial> <lp3.img.gz> <raw image size in bytes>
#   The raw size is the size of the uncompressed lp3.img (macOS: stat -f %z lp3.img).
# Then confirm the install on the phone (it must be awake and unlocked) and run wait-dsu-ready.sh.
# Writes: removes the installed DSU image and any *.img.gz in the phone's Download folder.
set -eu
S=$1; gz=$2; size=$3; name=$(basename "$gz")
# From inside the GSI this replaces the running image, and wait-dsu-ready.sh then reports the old one.
if [ -n "$(adb -s "$S" shell getprop ro.lineage.version </dev/null | tr -d '\r')" ]; then
  echo "in the GSI: run tools/to-lightos.sh first" >&2; exit 2
fi
adb -s "$S" shell gsi_tool wipe </dev/null || true
adb -s "$S" shell 'rm -f /storage/emulated/0/Download/*.img.gz' </dev/null
adb -s "$S" push "$gz" /storage/emulated/0/Download/"$name"
want=$(stat -f %z "$gz"); got=$(adb -s "$S" shell stat -c %s /storage/emulated/0/Download/"$name" </dev/null | tr -d '\r')
[ "$want" = "$got" ] || { echo "PUSH INCOMPLETE: $got of $want bytes"; exit 3; }
adb -s "$S" shell am start-activity -n com.android.dynsystem/com.android.dynsystem.VerificationActivity \
  -a android.os.image.action.START_INSTALL -d file:///storage/emulated/0/Download/"$name" \
  --el KEY_SYSTEM_SIZE "$size" --el KEY_USERDATA_SIZE 8589934592 </dev/null
