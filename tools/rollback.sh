#!/usr/bin/env bash
# Roll a fully flashed LP3 back to stock LightOS from your own verified partition dump (partition-dump.sh output
# with super, vbmeta_a and boot_a). See docs/full-flash.md.
# Writes: super (whole: restores LightOS system/product/system_ext/vendor/odm + lp metadata), vbmeta_a (stock bytes,
# no flags), boot_a (stock kernel), userdata/metadata erase. All from bootloader fastboot, slot a only.
# Usage: rollback.sh <serial> <step> <dump dir>
#   prep    decompress super, vbmeta_a and boot_a to $ROLLBACK_WORK (default ~/.cache/lp3-rollback) and verify
#           their sha256 against the dump manifest (no phone needed)
#   check   read-only: bootloader getvars (slot a, unlocked, super size)
#   flash   the writes, then reboot to LightOS
set -uo pipefail
S=${1:?serial}; step=${2:?prep|check|flash}; dump=${3:?dump dir}
work=${ROLLBACK_WORK:-$HOME/.cache/lp3-rollback}
die() { echo "STOP: $*"; exit 1; }
gv() { fastboot -s "$S" getvar "$1" 2>&1 | awk -F': ' -v k="$1" '$1==k {print $2}' | tr -d '\r'; }
wait_fb() { for i in $(seq 1 60); do fastboot devices | grep -q "$S" && return 0; sleep 2; done; die "no fastboot device"; }
want() { grep "^$1	OK	" "$dump/manifest.tsv" | cut -f5; }
verify() { [ "$(shasum -a 256 "$work/$1.img" | cut -d' ' -f1)" = "$(want "$1")" ] || die "$1 hash mismatch"; echo "$1 sha OK"; }

case "$step" in
prep)
  mkdir -p "$work"
  for p in super vbmeta_a boot_a; do [ -f "$work/$p.img" ] || zstd -q -d -f "$dump/$p.img.zst" -o "$work/$p.img"; verify "$p"; done;;
check)
  verify super; verify vbmeta_a; verify boot_a
  if adb devices | grep -q "^$S	device"; then adb -s "$S" reboot bootloader; fi
  wait_fb
  [ "$(gv is-userspace)" != yes ] || { fastboot -s "$S" reboot bootloader; sleep 3; wait_fb; }
  echo "bootloader: slot=$(gv current-slot) unlocked=$(gv unlocked) super=$(gv partition-size:super) maxdl=$(gv max-download-size)"
  [ "$(gv current-slot)" = a ] || die "slot not a"
  [ "$(gv unlocked)" = yes ] || die "not unlocked"
  [ $(( $(gv partition-size:super) )) = 6442450944 ] || die "super size"
  echo "ROLLBACK CHECK OK (in bootloader, nothing written)";;
flash)
  verify super; verify vbmeta_a; verify boot_a
  if adb devices | grep -q "^$S	device"; then adb -s "$S" reboot bootloader; fi
  wait_fb
  [ "$(gv is-userspace)" != yes ] || { fastboot -s "$S" reboot bootloader; sleep 3; wait_fb; }
  [ "$(gv current-slot)" = a ] || die "slot not a"
  fastboot -s "$S" flash super "$work/super.img" || die "super flash failed: stay in bootloader, report"
  fastboot -s "$S" flash vbmeta_a "$work/vbmeta_a.img" || die "vbmeta_a flash failed: stay in bootloader, report"
  fastboot -s "$S" flash boot_a "$work/boot_a.img" || die "boot_a flash failed: stay in bootloader, report"
  echo "after restore: slot=$(gv current-slot) snapshot=$(gv snapshot-update-status)"
  [ "$(gv current-slot)" = a ] || die "slot changed: stay in bootloader, report"
  # Not -w: the host formats userdata as ext4, the fstab wants f2fs -> "Can't load Android system".
  # Erased (blank) userdata + metadata are formatted on boot by fs_mgr with the fstab's own type.
  fastboot -s "$S" erase userdata || die "userdata erase failed"
  fastboot -s "$S" erase metadata || die "metadata erase failed"
  fastboot -s "$S" reboot
  echo "ROLLED BACK; booting LightOS";;
*) die "unknown step";;
esac
