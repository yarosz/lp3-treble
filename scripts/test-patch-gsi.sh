#!/usr/bin/env bash
# Self-test for patch-gsi.sh and pack-dsu.sh on a throwaway 160 MiB ext4 image shaped like a GSI. Needs only docker.
# shellcheck disable=SC2015  # "A && pass || fail": pass never fails
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
mkdir -p "$work/payload/system/product/etc/selinux"
echo '/system/bin/x u:object_r:system_file:s0' >"$work/payload/system/product/etc/selinux/product_file_contexts"
printf 'ro.lp3.test=1\npersist.lp3.test=on\n' >"$work/payload/build.prop.append"
printf '/system/lib64/libtest.so u:object_r:system_lib_file:s0 0755\r\n' >"$work/payload/contexts.txt"   # CRLF on purpose
# macOS junk that must be skipped, not injected, and not counted.
echo junk >"$work/payload/.DS_Store"; echo junk >"$work/payload/system/lib64/.DS_Store"; echo junk >"$work/payload/system/lib64/._libtest.so"

# Build the seed image like a GSI: no resize_inode/flex_bg/journal/metadata_csum, more than one
# block group, few inodes, a tail past the filesystem end, and pre-existing files with exotic
# labels, modes and owners (an overlay to replace, a sibling in /system/etc/permissions).
printf 'ro.build.type=userdebug\nro.treble.enabled=true\npersist.lp3.test=off' >"$work/seed.prop"   # no trailing newline
head -c 1000 /dev/urandom >"$work/old.apk"
printf '\n' >"$work/nl.txt"; : >"$work/empty.txt"
echo '<permissions/>' >"$work/old.xml"
cat >"$work/mkseed.sh" <<'EOS'
set -eu
rm -f /w/in.img; truncate -s 160M /w/in.img
mke2fs -q -t ext4 -b 4096 -N 64 -I 256 \
  -O none,ext_attr,dir_index,filetype,extent,sparse_super,large_file,huge_file,uninit_bg,dir_nlink,extra_isize \
  -L / /w/in.img
feat=$(dumpe2fs -h /w/in.img 2>/dev/null)
echo "seed $(echo "$feat" | grep '^Filesystem features:')"
for bad in flex_bg resize_inode has_journal metadata_csum; do
  echo "$feat" | grep '^Filesystem features:' | grep -qw "$bad" && { echo "seed has $bad"; exit 1; }
done
blocks=$(echo "$feat" | awk '/^Block count:/ {print $3}'); bpg=$(echo "$feat" | awk '/^Blocks per group:/ {print $4}')
[ $(( (blocks + bpg - 1) / bpg )) -gt 1 ] || { echo "seed has a single block group"; exit 1; }
echo "seed: $blocks blocks, $(( (blocks + bpg - 1) / bpg )) block groups"
dd if=/dev/urandom bs=1M count=3 >>/w/in.img 2>/dev/null   # tail past the fs end
lbl() { printf '%s\0' "$2" >"/tmp/l.$1"; }
lbl sys u:object_r:system_file:s0
lbl bp u:object_r:vendor_prop_file:s0
lbl ovl u:object_r:vendor_overlay_file:s0
lbl perm u:object_r:exotic_perm_file:s0
{
  for d in /system /system/product /system/product/overlay /system/etc /system/etc/permissions \
    /system/product/etc /system/product/etc/selinux; do
    echo "mkdir $d"; echo "set_inode_field $d mode 040755"; echo "ea_set -f /tmp/l.sys $d security.selinux"
  done
  echo "write /w/seed.prop /system/build.prop"
  echo "set_inode_field /system/build.prop mode 0100600"
  echo "ea_set -f /tmp/l.bp /system/build.prop security.selinux"
  echo "write /w/old.apk /system/product/overlay/treble-overlay-lp3.apk"
  echo "set_inode_field /system/product/overlay/treble-overlay-lp3.apk mode 0100755"
  echo "set_inode_field /system/product/overlay/treble-overlay-lp3.apk uid 1000"
  echo "set_inode_field /system/product/overlay/treble-overlay-lp3.apk gid 1001"
  echo "ea_set -f /tmp/l.ovl /system/product/overlay/treble-overlay-lp3.apk security.selinux"
  echo "write /w/old.xml /system/etc/permissions/seed.xml"
  echo "ea_set -f /tmp/l.perm /system/etc/permissions/seed.xml security.selinux"
  # The GSI ships these empty (one newline / zero bytes); a non-empty one must never be replaced.
  echo "write /w/nl.txt /system/product/etc/selinux/product_sepolicy.cil"
  echo "write /w/empty.txt /system/product/etc/selinux/product_file_contexts"
} >/tmp/c
debugfs -w -f /tmp/c /w/in.img >/dev/null
# Variant whose product_sepolicy.cil already has policy, for the refusal test.
cp /w/in.img /w/in_pol.img
printf '(type gsi_own)\n' >/w/pol.txt
debugfs -w -R "rm /system/product/etc/selinux/product_sepolicy.cil" /w/in_pol.img >/dev/null
debugfs -w -R "write /w/pol.txt /system/product/etc/selinux/product_sepolicy.cil" /w/in_pol.img >/dev/null
# Variant with shared_blocks set, for the refusal test.
cp /w/in.img /w/in_sb.img
debugfs -w -R "feature shared_blocks" /w/in_sb.img >/dev/null
EOS
docker run --rm -v "$work:/w" -e E2FS_PKGS="$E2FSPROGS_PKG $E2FSPROGS_EXTRA_PKG" "$ALPINE_IMAGE" \
  sh -c 'apk add --no-cache $E2FS_PKGS >/dev/null && sh /w/mkseed.sh'
in_sum_before=$(shasum -a 256 "$work/in.img" | cut -d' ' -f1)

echo "### run patch-gsi.sh"
"$here/patch-gsi.sh" "$work/in.img" "$work/out.img" "$work/payload" 2>&1 | tee "$work/main.log"

status=0
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
chk() { # chk <path> <exp mode> <exp ctx> <exp uid> <exp gid>
  p=$1
  st=$(debugfs -R "stat $p" $img 2>/dev/null)
  mode=$(echo "$st" | sed -n 's/^Inode:.*Mode: *\([0-7]*\).*/\1/p')
  uid=$(echo "$st" | sed -n 's/^User: *\([0-9]*\).*/\1/p')
  gid=$(echo "$st" | sed -n 's/^User:.*Group: *\([0-9]*\).*/\1/p')
  ctx=$(debugfs -R "ea_get $p security.selinux" $img 2>/dev/null | sed -n 's/.*= "\(.*\)\\000"$/\1/p')
  [ "$mode" = "$2" ] && ok "$p mode $mode" || bad "$p mode $mode (want $2)"
  [ "$uid/$gid" = "$4/$5" ] && ok "$p uid/gid $uid/$gid" || bad "$p uid/gid $uid/$gid (want $4/$5)"
  [ "$ctx" = "$3" ] && ok "$p selinux $ctx" || bad "$p selinux '$ctx' (want $3)"
  if [ -e "/w/exp.$(basename "$p").sha" ]; then
    debugfs -R "dump $p /tmp/d" $img >/dev/null 2>&1
    got=$(sha256sum /tmp/d | cut -d' ' -f1)
    exp=$(cat "/w/exp.$(basename "$p").sha")
    [ "$got" = "$exp" ] && ok "$p sha256 matches payload" || bad "$p sha256 differs"
  fi
}
# Replaced file keeps its exotic label, mode 0755 and owner 1000/1001.
chk /system/product/overlay/treble-overlay-lp3.apk 0755 u:object_r:vendor_overlay_file:s0 1000 1001
# New file in an existing dir inherits the sibling's label.
chk /system/etc/permissions/lp3-test.xml 0644 u:object_r:exotic_perm_file:s0 0 0
# New file in a new dir: the contexts.txt override (CRLF file) wins.
chk /system/lib64/libtest.so 0755 u:object_r:system_lib_file:s0 0 0
# Empty product_file_contexts replaced (sibling label: the seed left these unlabelled, so the table default).
debugfs -R "dump /system/product/etc/selinux/product_file_contexts /tmp/pfc" $img >/dev/null 2>&1
grep -q '^/system/bin/x ' /tmp/pfc && ok "empty product_file_contexts replaced" || bad "product_file_contexts not replaced"
# Untouched sibling.
chk /system/etc/permissions/seed.xml 0644 u:object_r:exotic_perm_file:s0 0 0
for d in /system/etc /system/etc/permissions /system/lib64; do
  want=u:object_r:system_file:s0
  [ "$d" = /system/lib64 ] && want=u:object_r:system_lib_file:s0
  m=$(debugfs -R "stat $d" $img 2>/dev/null | sed -n 's/^Inode:.*Mode: *\([0-7]*\).*/\1/p')
  c=$(debugfs -R "ea_get $d security.selinux" $img 2>/dev/null | sed -n 's/.*= "\(.*\)\\000"$/\1/p')
  [ "$m" = 0755 ] && [ "$c" = "$want" ] && ok "dir $d 0755 $c" || bad "dir $d mode=$m ctx=$c"
done
for j in /.DS_Store /system/lib64/.DS_Store /system/lib64/._libtest.so; do
  if debugfs -R "stat $j" $img 2>/dev/null | grep -q '^Inode:'; then bad "junk injected: $j"; else ok "junk skipped: $j"; fi
done
debugfs -R "dump /system/build.prop /tmp/bp" $img >/dev/null 2>&1
printf 'ro.build.type=userdebug\nro.treble.enabled=true\npersist.lp3.test=off\nro.lp3.test=1\npersist.lp3.test=on\n' >/tmp/bp.exp
cmp -s /tmp/bp /tmp/bp.exp && ok "build.prop = original + appended lines (newline-joined)" || { bad "build.prop content"; cat /tmp/bp; }
chk /system/build.prop 0600 u:object_r:vendor_prop_file:s0 0 0
inodes=$(dumpe2fs -h $img 2>/dev/null | awk '/^Inode count:/ {print $3}')
echo "inode count in output: $inodes (seed had 64)"
e2fsck -fn $img >/tmp/e.log 2>&1 && ok "e2fsck -fn clean: $(tail -1 /tmp/e.log)" || { bad "e2fsck"; cat /tmp/e.log; }
exit $fail
EOS
docker run --rm -v "$work:/w:ro" -e E2FS_PKGS="$E2FSPROGS_PKG $E2FSPROGS_EXTRA_PKG" "$ALPINE_IMAGE" sh /w/verify.sh || status=1

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; status=1; }
if [ "$in_sum_before" = "$in_sum_after" ]; then pass "input image untouched"; else fail "input image modified"; fi
grep -q 'skipping macOS junk file: .DS_Store' "$work/main.log" && pass "junk skip noted" || fail "junk skip note missing"
grep -q 'payload: 4 file(s)' "$work/main.log" && pass "junk excluded from payload count (4)" || fail "payload count line"
grep -q 'lp3-test.xml label u:object_r:exotic_perm_file:s0 (from sibling) differs' "$work/main.log" && pass "sibling label note printed" || fail "sibling note missing"
grep -q 'treble-overlay-lp3.apk label u:object_r:vendor_overlay_file:s0 (from existing) differs' "$work/main.log" && pass "existing label note printed" || fail "existing note missing"
grep -q 'warning: persist.lp3.test is already' "$work/main.log" && pass "non-ro duplicate warned" || fail "non-ro duplicate warning missing"

echo
echo "### refusals (each must fail, leave no output, and say why)"
o="$work/o.img"
expect_fail() { # expect_fail <name> <message pattern> <cmd...>
  name=$1 pat=$2; shift 2
  rm -f "$o"
  if "$@" >"$work/fail.log" 2>&1; then fail "$name: succeeded but should refuse"; rm -f "$o"; return; fi
  if grep -q -- "$pat" "$work/fail.log"; then pass "$name refused ($pat)"; else fail "$name: wrong message"; cat "$work/fail.log"; fi
  if [ -e "$o" ]; then fail "$name left an output file"; rm -f "$o"; fi
}
patch() { "$here/patch-gsi.sh" "$@"; }
newpayload() { rm -rf "$work/p2"; cp -R "$work/payload" "$work/p2"; }

LP3_TREBLE_SHARED_ROOTS=/nonexistent-root expect_fail "path outside shared roots" "colima" \
  patch "$work/in.img" "$o" "$work/payload"
LP3_TREBLE_FORCE_PAYLOAD_COUNT=99 expect_fail "payload count mismatch (empty-mount simulation)" "payload mismatch" \
  patch "$work/in.img" "$o" "$work/payload"
newpayload; ln -s libtest.so "$work/p2/system/lib64/link.so"
expect_fail "symlink in payload" "not regular files" patch "$work/in.img" "$o" "$work/p2"
newpayload; printf '/system/bin/x u:object_r:Bad-Type:s0 0755\r\n/system/bin/y u:object_r:system_file:s0 4755\n' >"$work/p2/contexts.txt"
expect_fail "bad contexts label" "contexts.txt line 1: bad label" patch "$work/in.img" "$o" "$work/p2"
expect_fail "bad contexts mode (setuid)" "contexts.txt line 2: bad mode" patch "$work/in.img" "$o" "$work/p2"
rm -rf "$work/p3"; mkdir -p "$work/p3"
expect_fail "empty payload" "nothing to inject" patch "$work/in.img" "$o" "$work/p3"
rm -rf "$work/p4"; mkdir -p "$work/p4"; printf 'ro.build.type=user\n' >"$work/p4/build.prop.append"
expect_fail "ro.* duplicate in build.prop.append" "ro.build.type" patch "$work/in.img" "$o" "$work/p4"
# Same seed with a non-empty product_sepolicy.cil: the patcher must refuse to replace it.
rm -rf "$work/p5"; mkdir -p "$work/p5/system/product/etc/selinux"; echo '(type x)' >"$work/p5/system/product/etc/selinux/product_sepolicy.cil"
expect_fail "non-empty product_sepolicy.cil" "is not empty" patch "$work/in_pol.img" "$o" "$work/p5"
if [ -f "$work/in_sb.img" ]; then
  expect_fail "shared_blocks image" "shared_blocks" patch "$work/in_sb.img" "$o" "$work/payload"
else
  echo "SKIP shared_blocks (debugfs could not set the feature)"
fi

echo
echo "### pack-dsu.sh"
"$here/pack-dsu.sh" "$work/out.img" "$work/out.img.gz" | tee "$work/pack.log" | sed -n '1p;/START_INSTALL/p;/KEY_SYSTEM_SIZE/p'
if gzip -dc "$work/out.img.gz" | cmp -s - "$work/out.img"; then pass "gzip round-trips"; else fail "gzip round-trip"; fi
if [ ! -e "$work/out.img.gz.tmp" ]; then pass "no .tmp left behind"; else fail ".tmp left behind"; fi
sp=$(grep -n 'setprop persist.sys.fflag.override.settings_dynamic_system true' "$work/pack.log" | cut -d: -f1)
st=$(grep -n 'am start-activity' "$work/pack.log" | cut -d: -f1)
if [ -n "$sp" ] && [ -n "$st" ] && [ "$sp" -lt "$st" ]; then pass "setprop line precedes start-activity"; else fail "setprop line missing or misplaced"; fi
grep -q 'adb push ".*out.img.gz"' "$work/pack.log" && pass "file name quoted" || fail "file name not quoted"

echo
if [ "$status" -eq 0 ]; then echo "SELF-TEST PASSED"; else echo "SELF-TEST FAILED"; exit 1; fi
