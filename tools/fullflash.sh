#!/usr/bin/env bash
# Full flash of a patched lp3-treble image onto slot a, as in docs/full-flash.md. Read that page first.
# Writes ONLY: system_a (the image), vbmeta_a (your stock dump + --disable-verity --disable-verification), userdata +
# metadata erase (never `fastboot -w` on the LP3). Never abl/xbl/firmware, never lock, never super wholesale.
# Usage: fullflash.sh <serial> <step> <dump dir> <lp3.img>
#   dump dir  partition-dump.sh output with OK rows for super, vbmeta_a and boot_a; run
#             `rollback.sh <serial> prep <dump dir>` first, which decompresses all three into $ROLLBACK_WORK
#             (default ~/.cache/lp3-rollback) and verifies them. This script re-verifies them before anything else.
#   lp3.img   the raw patched image (not the .gz)
#   dryrun    read-only: checks the bootloader (slot a, unlocked, no snapshot update) and prints the fastbootd values
#             (system_a size, max download). It doesn't compute free space in super.
#   flash     bootloader checks, then fastbootd `flash system` first. That is the fit check: fastbootd refuses an
#             image that doesn't fit super, and then nothing has been written. Then the bootloader: vbmeta_a with
#             the flags, erase userdata + metadata, reboot into the GSI.
set -uo pipefail
S=${1:?serial}; step=${2:?dryrun|flash}; dump=${3:?dump dir}; img=${4:?lp3.img}
work=${ROLLBACK_WORK:-$HOME/.cache/lp3-rollback}
die() { echo "STOP: $*"; exit 1; }
. "$(dirname "$0")/dump-lib.sh"

case "$img" in *.gz) die "use the raw image, not the .gz";; esac
[ -s "$img" ] || die "no image: $img"
verify_all  # no rollback possible without all three

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
  fastboot -s "$S" reboot fastboot; wait_mode yes
  echo "fastbootd: userspace=$(gv is-userspace) super-name=$(gv super-partition-name) system_a=$(gv partition-size:system_a) logical=$(gv is-logical:system_a) maxdl=$(gv max-download-size)"
  fastboot -s "$S" reboot
  echo "DRYRUN OK (nothing written)";;
flash)
  to_bootloader; check_bootloader
  fastboot -s "$S" reboot fastboot; wait_mode yes
  [ "$(gv current-slot)" = a ] || die "fastbootd slot not a (nothing written)"
  fastboot -s "$S" flash system "$img" || die "system flash failed or refused (if refused, nothing written; else run rollback.sh)"
  fastboot -s "$S" reboot bootloader; wait_mode no
  [ "$(gv current-slot)" = a ] || die "slot changed: stay in bootloader, run rollback.sh"
  fastboot -s "$S" --disable-verity --disable-verification flash vbmeta_a "$work/vbmeta_a.img" || die "vbmeta_a flash failed: run rollback.sh"
  fastboot -s "$S" erase userdata || die "userdata erase failed: run rollback.sh"
  fastboot -s "$S" erase metadata || die "metadata erase failed: run rollback.sh"
  fastboot -s "$S" reboot
  echo "FLASHED; booting the GSI";;
*) die "unknown step";;
esac
