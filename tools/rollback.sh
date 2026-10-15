#!/usr/bin/env bash
# Roll a fully flashed LP3 back to stock LightOS from your own verified partition dump (partition-dump.sh output
# with super, vbmeta_a and boot_a). See docs/full-flash.md.
# Writes: super (whole: restores LightOS system/product/system_ext/vendor/odm + lp metadata), vbmeta_a (stock bytes,
# no flags), boot_a (stock kernel), userdata/metadata erase. All from bootloader fastboot, slot a only.
# Usage: rollback.sh <serial> <step> <dump dir>
#   prep    decompress super, vbmeta_a and boot_a to $ROLLBACK_WORK (default ~/.cache/lp3-rollback) and verify
#           their sha256 against the dump manifest's OK rows (no phone needed)
#   check   read-only: bootloader getvars (slot a, unlocked, no snapshot update, super size)
#   flash   the same checks, then the writes, then reboot to LightOS
set -uo pipefail
S=${1:?serial}; step=${2:?prep|check|flash}; dump=${3:?dump dir}
work=${ROLLBACK_WORK:-$HOME/.cache/lp3-rollback}
die() { echo "STOP: $*"; exit 1; }
. "$(dirname "$0")/dump-lib.sh"
check_bootloader() {
  echo "bootloader: slot=$(gv current-slot) unlocked=$(gv unlocked) snapshot=$(gv snapshot-update-status) super=$(gv partition-size:super) maxdl=$(gv max-download-size)"
  [ "$(gv current-slot)" = a ] || die "slot not a"
  [ "$(gv unlocked)" = yes ] || die "not unlocked"
  [ "$(gv snapshot-update-status)" = none ] || die "snapshot update pending"
  [ $(( $(gv partition-size:super) )) = 6442450944 ] || die "super size"
}

case "$step" in
prep)
  mkdir -p "$work"
  for p in $parts; do
    [ -n "$(want "$p")" ] || die "no OK row for $p in $dump/manifest.tsv"
    if [ ! -s "$work/$p.img" ]; then
      [ -s "$dump/$p.img.zst" ] || die "$dump/$p.img.zst missing"
      zstd -q -d -f "$dump/$p.img.zst" -o "$work/$p.img" || { rm -f "$work/$p.img"; die "$p: zstd -d failed"; }
    fi
    verify "$p"
  done;;
check)
  verify_all
  to_bootloader; check_bootloader
  echo "ROLLBACK CHECK OK (in bootloader, nothing written)";;
flash)
  verify_all
  to_bootloader; check_bootloader
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
  echo "ROLLED BACK; booting LightOS"
  echo "LightOS setup follows with updates turned back on: never take an offered update. Skip Wi-Fi (airplane mode"
  echo "if a SIM has data), get adb back (*7412369#, Settings > Debug > Android Dev Mode, Allow), then run:"
  echo "  adb -s $S shell pm disable-user com.lightos.fota"
  echo "and connect Wi-Fi only after that. Steps: README.md, 'After a wipe: LightOS setup'."
  ;;
*) die "unknown step";;
esac
