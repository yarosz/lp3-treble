#!/bin/sh
# Runs INSIDE the Alpine container. Do not call directly; use scripts/patch-gsi.sh.
# Mounts: /img (rw, holds the output image), /payload (ro), /tmp scratch.
# Env: IMG_NAME, MARGIN_MIB, BUILD_PROP_PATH, E2FS_PKGS
set -eu

IMG="/img/$IMG_NAME"
PAYLOAD=/payload
W=/tmp/work
mkdir -p "$W"

# shellcheck disable=SC2086  # E2FS_PKGS is a space-separated package list
apk add --no-cache $E2FS_PKGS >/dev/null
echo "e2fsprogs: $(dumpe2fs -V 2>&1 | head -1)"

# Default labels by path. A payload/contexts.txt line is "path context [mode]";
# path is an image path ("/system/bin/x") or a dir prefix ending in "/". First match wins.
default_ctx() {
  case "$1" in
    /system/lib/*|/system/lib64/*) echo u:object_r:system_lib_file:s0 ;;
    *) echo u:object_r:system_file:s0 ;;
  esac
}
lookup() { # lookup <path> <field 2|3>
  [ -f "$PAYLOAD/contexts.txt" ] || return 0
  awk -v p="$1" -v f="$2" '
    /^[ \t]*(#|$)/ { next }
    { k=$1; if (k==p || (substr(k,length(k),1)=="/" && index(p,k)==1)) { print $f; exit } }' "$PAYLOAD/contexts.txt"
}
ctx_for() { c=$(lookup "$1" 2); if [ -n "$c" ]; then echo "$c"; else default_ctx "$1"; fi; }
mode_for() { m=$(lookup "$1" 3); if [ -n "$m" ]; then echo "$m"; else echo 0644; fi; }

exists() { debugfs -R "stat $1" "$IMG" 2>/dev/null | grep -q '^Inode:'; }

echo "== precheck"
rc=0
e2fsck -fy "$IMG" >"$W/pre.log" 2>&1 || rc=$?
if [ "$rc" -gt 1 ]; then cat "$W/pre.log"; echo "error: precheck failed (rc=$rc)"; exit 1; fi
tail -1 "$W/pre.log"

# Payload inventory.
( cd "$PAYLOAD" && find . -type f ! -path ./build.prop.append ! -path ./contexts.txt | sed 's|^\.||' | LC_ALL=C sort ) >"$W/files"
nfiles=$(wc -l <"$W/files")
payload_bytes=0
while IFS= read -r f; do
  s=$(wc -c <"$PAYLOAD$f"); payload_bytes=$((payload_bytes + s))
done <"$W/files"
if [ -f "$PAYLOAD/build.prop.append" ]; then
  payload_bytes=$((payload_bytes + $(wc -c <"$PAYLOAD/build.prop.append")))
fi

echo "== grow"
cur=$(wc -c <"$IMG")
# 2x payload (block rounding, dir blocks) + margin, rounded up to 4096.
want=$(( cur + 2 * payload_bytes + MARGIN_MIB * 1048576 ))
want=$(( (want + 4095) / 4096 * 4096 ))
truncate -s "$want" "$IMG"
e2fsck -fy "$IMG" >/dev/null 2>&1 || true
resize2fs "$IMG" >"$W/resize.log" 2>&1 || { cat "$W/resize.log"; exit 1; }
grep . "$W/resize.log" | tail -1 || true
echo "image: $cur -> $want bytes"
free_inodes=$(dumpe2fs -h "$IMG" 2>/dev/null | awk '/^Free inodes:/ {print $3}')
need_inodes=$((nfiles + 64))
if [ "$free_inodes" -lt "$need_inodes" ]; then
  echo "error: $free_inodes free inodes, need >= $need_inodes (raise MARGIN_MIB)"; exit 1
fi
echo "free inodes: $free_inodes"

echo "== inject"
: >"$W/cmds"; : >"$W/summary"; : >"$W/dirs.done"
n=0
mkctx() { # mkctx <ctx> -> path of a NUL-terminated file holding it
  f="$W/ctx.$(printf '%s' "$1" | tr -c 'A-Za-z0-9' _)"
  [ -f "$f" ] || printf '%s\0' "$1" >"$f"
  echo "$f"
}
mkdirs() { # mkdirs <dir path>: create missing parents, label the new ones
  acc=""
  oldIFS=$IFS; IFS=/
  # shellcheck disable=SC2086
  set -- $1
  IFS=$oldIFS
  for part in "$@"; do
    [ -n "$part" ] || continue
    acc="$acc/$part"
    grep -qxF "$acc" "$W/dirs.done" && continue
    echo "$acc" >>"$W/dirs.done"
    if ! exists "$acc"; then
      {
        echo "mkdir $acc"
        echo "set_inode_field $acc mode 040755"
        echo "set_inode_field $acc uid 0"
        echo "set_inode_field $acc gid 0"
        echo "ea_set -f $(mkctx "$(ctx_for "$acc/")") $acc security.selinux"
      } >>"$W/cmds"
      echo "mkdir  $acc" >>"$W/summary"
    fi
  done
}
while IFS= read -r f; do
  case "$f" in *[[:space:]]*) echo "error: whitespace in payload path: $f"; exit 1 ;; esac
  if [ -L "$PAYLOAD$f" ]; then echo "error: symlink in payload: $f"; exit 1; fi
  mkdirs "$(dirname "$f")"
  if exists "$f"; then echo "rm $f" >>"$W/cmds"; fi
  ctx=$(ctx_for "$f"); mode=$(mode_for "$f")
  {
    echo "write $PAYLOAD$f $f"
    echo "set_inode_field $f mode 0100${mode#0}"
    echo "set_inode_field $f uid 0"
    echo "set_inode_field $f gid 0"
    echo "ea_set -f $(mkctx "$ctx") $f security.selinux"
  } >>"$W/cmds"
  echo "file   $f  mode=$mode ctx=$ctx" >>"$W/summary"
  n=$((n + 1))
done <"$W/files"

bp_note=""
if [ -f "$PAYLOAD/build.prop.append" ]; then
  exists "$BUILD_PROP_PATH" || { echo "error: $BUILD_PROP_PATH not in image"; exit 1; }
  debugfs -R "dump $BUILD_PROP_PATH $W/build.prop.orig" "$IMG" >/dev/null 2>&1
  bpmode=$(debugfs -R "stat $BUILD_PROP_PATH" "$IMG" 2>/dev/null | sed -n 's/^Inode:.*Mode: *\([0-7]*\).*/\1/p')
  cp "$W/build.prop.orig" "$W/build.prop.new"
  if [ -n "$(tail -c1 "$W/build.prop.new")" ]; then echo >>"$W/build.prop.new"; fi
  cat "$PAYLOAD/build.prop.append" >>"$W/build.prop.new"
  if [ -n "$(tail -c1 "$W/build.prop.new")" ]; then echo >>"$W/build.prop.new"; fi
  bpctx=$(ctx_for "$BUILD_PROP_PATH")
  {
    echo "rm $BUILD_PROP_PATH"
    echo "write $W/build.prop.new $BUILD_PROP_PATH"
    echo "set_inode_field $BUILD_PROP_PATH mode 0100${bpmode#0}"
    echo "set_inode_field $BUILD_PROP_PATH uid 0"
    echo "set_inode_field $BUILD_PROP_PATH gid 0"
    echo "ea_set -f $(mkctx "$bpctx") $BUILD_PROP_PATH security.selinux"
  } >>"$W/cmds"
  nl=$(grep -c '^[^#[:space:]]' "$PAYLOAD/build.prop.append" || true)
  bp_note="$nl line(s) appended to $BUILD_PROP_PATH (mode $bpmode)"
  echo "append $BUILD_PROP_PATH  $bp_note" >>"$W/summary"
fi

debugfs -w -f "$W/cmds" "$IMG" >"$W/dbg.log" 2>&1 || true
# debugfs echoes each command ("debugfs: ...") then any error text; flag anything else.
if grep -Ev '^debugfs [0-9]|^debugfs: |^Allocated inode: |^$' "$W/dbg.log" | grep -q .; then
  grep -Ev '^debugfs [0-9]|^debugfs: |^Allocated inode: |^$' "$W/dbg.log"
  echo "error: debugfs reported problems"; exit 1
fi

echo "== verify"
while IFS= read -r f; do
  debugfs -R "dump $f $W/chk" "$IMG" >/dev/null 2>&1
  cmp -s "$PAYLOAD$f" "$W/chk" || { echo "error: content mismatch: $f"; exit 1; }
  want_ctx=$(ctx_for "$f")
  got=$(debugfs -R "ea_get $f security.selinux" "$IMG" 2>/dev/null | sed -n 's/.*= "\(.*\)\\000"$/\1/p')
  [ "$got" = "$want_ctx" ] || { echo "error: selinux label mismatch on $f: '$got'"; exit 1; }
done <"$W/files"
if [ -f "$PAYLOAD/build.prop.append" ]; then
  debugfs -R "dump $BUILD_PROP_PATH $W/chk" "$IMG" >/dev/null 2>&1
  cmp -s "$W/chk" "$W/build.prop.new" || { echo "error: build.prop mismatch"; exit 1; }
fi
e2fsck -fn "$IMG" >"$W/post.log" 2>&1 || { cat "$W/post.log"; echo "error: e2fsck -fn not clean after patch"; exit 1; }
tail -1 "$W/post.log"

echo "== summary"
cat "$W/summary"
echo "injected $n file(s)"
if [ -n "$bp_note" ]; then echo "$bp_note"; fi
