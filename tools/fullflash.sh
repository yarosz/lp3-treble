#!/usr/bin/env bash
# Full flash of a patched lp3-treble image onto slot a, as in docs/full-flash.md. Read that page first.
# Writes ONLY: vbmeta_a (your stock dump + --disable-verity --disable-verification), system_a (the image), userdata +
# metadata erase (never `fastboot -w` on the LP3). Never abl/xbl/firmware, never lock, never super wholesale.
# Usage: fullflash.sh <serial> <step> <dump dir> <lp3.img>
#   dump dir  partition-dump.sh output holding super and vbmeta_a; run `rollback.sh <serial> prep <dump dir>` first,
#             which decompresses vbmeta_a into $ROLLBACK_WORK (default ~/.cache/lp3-rollback) and verifies it
#   lp3.img   the raw patched image (not the .gz)
#   dryrun    read-only: bootloader + fastbootd getvars (slot a, unlocked, no snapshot, system_a size, super free)
#   flash     the writes, then reboot into the GSI
set -uo pipefail
S=${1:?serial}; step=${2:?dryrun|flash}; dump=${3:?dump dir}; img=${4:?lp3.img}
vbm=${ROLLBACK_WORK:-$HOME/.cache/lp3-rollback}/vbmeta_a.img
die() { echo "STOP: $*"; exit 1; }
gv() { fastboot -s "$S" getvar "$1" 2>&1 | awk -F': ' -v k="$1" '$1==k {print $2}' | tr -d '\r'; }
wait_fb() { for i in $(seq 1 60); do fastboot devices | grep -q "$S" && return 0; sleep 2; done; die "no fastboot device"; }
want() { grep "^$1	OK	" "$dump/manifest.tsv" | cut -f5; }

case "$img" in *.gz) die "use the raw image, not the .gz";; esac
[ -s "$img" ] || die "no image: $img"
[ -n "$(want super)" ] || die "no verified super in the dump: no rollback possible"
[ "$(shasum -a 256 "$vbm" | cut -d' ' -f1)" = "$(want vbmeta_a)" ] || die "vbmeta_a hash (run rollback.sh prep first)"

to_bootloader() {
  if adb devices | grep -q "^$S	device"; then adb -s "$S" reboot bootloader; fi
  wait_fb
  [ "$(gv is-userspace)" != yes ] || { fastboot -s "$S" reboot bootloader; sleep 3; wait_fb; }
}
check_bootloader() {
  echo "bootloader: slot=$(gv current-slot) unlocked=$(gv unlocked) snapshot=$(gv snapshot-update-status) super=$(gv partition-size:super)"
  [ "$(gv current-slot)" = a ] || die "slot not a"
  [ "$(gv unlocked)" = yes ] || die "not unlocked"
  [ "$(gv snapshot-update-status)" = none ] || die "snapshot update pending"
  # `fastboot -w` formats with the bootloader's type; on the LP3 that is ext4 while the fstab wants f2fs.
  echo "bootloader partition-type:userdata=$(gv partition-type:userdata) (fstab: f2fs; never -w on a mismatch)"
}

case "$step" in
dryrun)
  to_bootloader; check_bootloader
  fastboot -s "$S" reboot fastboot; sleep 3; wait_fb
  echo "fastbootd: userspace=$(gv is-userspace) super-name=$(gv super-partition-name) system_a=$(gv partition-size:system_a) logical=$(gv is-logical:system_a) maxdl=$(gv max-download-size)"
  [ "$(gv is-userspace)" = yes ] || die "fastbootd not reached"
  fastboot -s "$S" reboot
  echo "DRYRUN OK (nothing written)";;
flash)
  to_bootloader; check_bootloader
  fastboot -s "$S" --disable-verity --disable-verification flash vbmeta_a "$vbm" || die "vbmeta_a flash failed (rollback: flash the stock vbmeta_a)"
  fastboot -s "$S" reboot fastboot; sleep 3; wait_fb
  [ "$(gv is-userspace)" = yes ] || die "fastbootd not reached"
  fastboot -s "$S" flash system "$img" || die "system flash failed: run rollback.sh"
  fastboot -s "$S" reboot bootloader; sleep 3; wait_fb
  fastboot -s "$S" erase userdata || die "userdata erase failed: run rollback.sh"
  fastboot -s "$S" erase metadata || die "metadata erase failed: run rollback.sh"
  fastboot -s "$S" reboot
  echo "FLASHED; booting the GSI";;
*) die "unknown step";;
esac
