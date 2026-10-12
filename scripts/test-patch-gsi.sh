#!/usr/bin/env bash
# Self-test for patch-gsi.sh and pack-dsu.sh on a throwaway 64 MiB ext4 image. Needs only docker.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

case "${1:-}" in
  -h|--help) echo "Usage: test-patch-gsi.sh   (builds a temp ext4 image in a container, runs patch-gsi.sh, verifies)"; exit 0 ;;
  "") ;;
  *) echo "Usage: test-patch-gsi.sh" >&2; exit 64 ;;
esac
need_docker

# colima shares only $HOME with the VM, so the scratch dir must live under it.
base=${LP3_TEST_TMP:-$HOME/.cache/lp3-treble-test}
mkdir -p "$base"
work=$(mktemp -d "$base/run.XXXXXX")
work=$(abspath "$work")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/payload/system/product/overlay" "$work/payload/system/etc/permissions" "$work/payload/system/lib64"

# Dummy payload: random "apk", an XML, a lib (label override via table), build.prop.append, contexts.txt.
head -c 123457 /dev/urandom >"$work/payload/system/product/overlay/treble-overlay-lp3.apk"
cat >"$work/payload/system/etc/permissions/lp3-test.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<permissions>
    <feature name="android.software.credentials" />
</permissions>
XML
head -c 4097 /dev/urandom >"$work/payload/system/lib64/libtest.so"
printf 'ro.lp3.test=1\npersist.lp3.test=on\n' >"$work/payload/build.prop.append"
printf '/system/lib64/libtest.so u:object_r:system_lib_file:s0 0755\n' >"$work/payload/contexts.txt"

# Build the seed image: few inodes on purpose, with /system/build.prop and a preexisting overlay
# at the path the payload replaces.
printf 'ro.build.type=userdebug\nro.treble.enabled=true' >"$work/seed.prop"   # no trailing newline
head -c 1000 /dev/urandom >"$work/old.apk"
cat >"$work/mkseed.sh" <<'EOS'
set -eu
rm -f /w/in.img; truncate -s 64M /w/in.img
mke2fs -q -t ext4 -b 4096 -N 64 -O ^has_journal,^metadata_csum -L / /w/in.img
printf 'u:object_r:system_file:s0\0' >/tmp/ctx
cat >/tmp/c <<'C'
mkdir /system
mkdir /system/product
mkdir /system/product/overlay
write /w/seed.prop /system/build.prop
set_inode_field /system/build.prop mode 0100600
ea_set -f /tmp/ctx /system/build.prop security.selinux
write /w/old.apk /system/product/overlay/treble-overlay-lp3.apk
ea_set -f /tmp/ctx /system/product/overlay/treble-overlay-lp3.apk security.selinux
C
debugfs -w -f /tmp/c /w/in.img >/dev/null
EOS
docker run --rm -v "$work:/w" -e E2FS_PKGS="$E2FSPROGS_PKG $E2FSPROGS_EXTRA_PKG" "$ALPINE_IMAGE" \
  sh -c 'apk add --no-cache $E2FS_PKGS >/dev/null && sh /w/mkseed.sh'
in_sum_before=$(shasum -a 256 "$work/in.img" | cut -d' ' -f1)

echo "### run patch-gsi.sh"
"$here/patch-gsi.sh" "$work/in.img" "$work/out.img" "$work/payload"

echo
echo "### verify"
in_sum_after=$(shasum -a 256 "$work/in.img" | cut -d' ' -f1)
for f in system/product/overlay/treble-overlay-lp3.apk system/etc/permissions/lp3-test.xml system/lib64/libtest.so; do
  shasum -a 256 "$work/payload/$f" | cut -d' ' -f1 >"$work/exp.$(basename "$f").sha"
done

cat >"$work/verify.sh" <<'EOS'
set -eu
apk add --no-cache $E2FS_PKGS >/dev/null
fail=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
img=/w/out.img
chk() { # chk <path> <exp mode> <exp ctx>
  p=$1
  st=$(debugfs -R "stat $p" $img 2>/dev/null)
  mode=$(echo "$st" | sed -n 's/^Inode:.*Mode: *\([0-7]*\).*/\1/p')
  uid=$(echo "$st" | sed -n 's/^User: *\([0-9]*\).*/\1/p')
  gid=$(echo "$st" | sed -n 's/^User:.*Group: *\([0-9]*\).*/\1/p')
  ctx=$(debugfs -R "ea_get $p security.selinux" $img 2>/dev/null | sed -n 's/.*= "\(.*\)\\000"$/\1/p')
  [ "$mode" = "$2" ] && ok "$p mode $mode" || bad "$p mode $mode (want $2)"
  [ "$uid" = 0 ] && [ "$gid" = 0 ] && ok "$p uid/gid 0/0" || bad "$p uid/gid $uid/$gid"
  [ "$ctx" = "$3" ] && ok "$p selinux $ctx" || bad "$p selinux '$ctx' (want $3)"
  debugfs -R "dump $p /tmp/d" $img >/dev/null 2>&1
  got=$(sha256sum /tmp/d | cut -d' ' -f1)
  exp=$(cat "/w/exp.$(basename "$p").sha")
  [ "$got" = "$exp" ] && ok "$p sha256 matches payload" || bad "$p sha256 differs"
}
chk /system/product/overlay/treble-overlay-lp3.apk 0644 u:object_r:system_file:s0
chk /system/etc/permissions/lp3-test.xml 0644 u:object_r:system_file:s0
chk /system/lib64/libtest.so 0755 u:object_r:system_lib_file:s0
for d in /system/etc /system/etc/permissions /system/lib64; do
  want=u:object_r:system_file:s0
  [ "$d" = /system/lib64 ] && want=u:object_r:system_lib_file:s0
  m=$(debugfs -R "stat $d" $img 2>/dev/null | sed -n 's/^Inode:.*Mode: *\([0-7]*\).*/\1/p')
  c=$(debugfs -R "ea_get $d security.selinux" $img 2>/dev/null | sed -n 's/.*= "\(.*\)\\000"$/\1/p')
  [ "$m" = 0755 ] && [ "$c" = "$want" ] && ok "dir $d 0755 $c" || bad "dir $d mode=$m ctx=$c"
done
debugfs -R "dump /system/build.prop /tmp/bp" $img >/dev/null 2>&1
printf 'ro.build.type=userdebug\nro.treble.enabled=true\nro.lp3.test=1\npersist.lp3.test=on\n' >/tmp/bp.exp
cmp -s /tmp/bp /tmp/bp.exp && ok "build.prop = original + appended lines (newline-joined)" || { bad "build.prop content"; cat /tmp/bp; }
bm=$(debugfs -R "stat /system/build.prop" $img 2>/dev/null | sed -n 's/^Inode:.*Mode: *\([0-7]*\).*/\1/p')
[ "$bm" = 0600 ] && ok "build.prop mode preserved 0600" || bad "build.prop mode $bm"
inodes=$(dumpe2fs -h $img 2>/dev/null | awk '/^Inode count:/ {print $3}')
echo "inode count in output: $inodes (seed had 64)"
e2fsck -fn $img >/tmp/e.log 2>&1 && ok "e2fsck -fn clean: $(tail -1 /tmp/e.log)" || { bad "e2fsck"; cat /tmp/e.log; }
exit $fail
EOS
docker run --rm -v "$work:/w:ro" -e E2FS_PKGS="$E2FSPROGS_PKG $E2FSPROGS_EXTRA_PKG" "$ALPINE_IMAGE" sh /w/verify.sh

status=0
if [ "$in_sum_before" = "$in_sum_after" ]; then echo "PASS input image untouched"; else echo "FAIL input image modified"; status=1; fi

echo
echo "### pack-dsu.sh"
"$here/pack-dsu.sh" "$work/out.img" "$work/out.img.gz" | sed -n '1p;/START_INSTALL/p;/KEY_SYSTEM_SIZE/p'
if gzip -dc "$work/out.img.gz" | cmp -s - "$work/out.img"; then echo "PASS gzip round-trips"; else echo "FAIL gzip round-trip"; status=1; fi

echo
if [ "$status" -eq 0 ]; then echo "SELF-TEST PASSED"; else echo "SELF-TEST FAILED"; exit 1; fi
