#!/bin/sh
# Runs INSIDE the Alpine container. Do not call directly; use scripts/patch-gsi.sh.
# Mounts: /img (rw, holds the output image), /payload (ro), /container (ro), /tmp scratch.
# Env: IMG_NAME, MARGIN_MIB, BUILD_PROP_PATH, E2FS_PKGS, PAYLOAD_COUNT, PAYLOAD_APPEND,
#      HAS_AVB (1: AVBTOOL and PYTHON3_PKG set, /avb mounted ro)
set -eu

IMG="/img/$IMG_NAME"
PAYLOAD=/payload
W=/tmp/work
mkdir -p "$W"
# shellcheck source-path=SCRIPTDIR source=payload-list.sh
. /container/payload-list.sh

die() { echo "error: $*"; exit 1; }

echo "== payload"
HINT="is the payload/output dir under a path the VM mounts? colima shares only \$HOME"
[ -s "$IMG" ] || die "image not visible in the container ($IMG); $HINT"
[ -d "$PAYLOAD" ] || die "payload not visible in the container; $HINT"
special=$(payload_special "$PAYLOAD")
if [ -n "$special" ]; then
  echo "$special" | sed 's/^/  /'
  die "payload has entries that are not regular files or directories (symlink, fifo, device)"
fi
payload_files "$PAYLOAD" >"$W/files"
nfiles=$(wc -l <"$W/files" | tr -d ' ')
have_append=0
if [ -f "$PAYLOAD/build.prop.append" ]; then have_append=1; fi
if [ "$nfiles" != "$PAYLOAD_COUNT" ] || [ "$have_append" != "$PAYLOAD_APPEND" ]; then
  die "payload mismatch: host saw $PAYLOAD_COUNT file(s) + build.prop.append=$PAYLOAD_APPEND, container sees $nfiles + $have_append; $HINT"
fi
if [ "$nfiles" -eq 0 ] && [ "$have_append" -eq 0 ]; then die "nothing to inject"; fi
if grep -q '[[:space:]]' "$W/files"; then die "whitespace in a payload path (unsupported)"; fi
echo "payload: $nfiles file(s), build.prop.append=$have_append"

# contexts.txt: strip CR, validate (also done on the host before the copy).
if [ -f "$PAYLOAD/contexts.txt" ]; then
  awk -f /container/validate-contexts.awk "$PAYLOAD/contexts.txt" >&2 || exit 1
  tr -d '\r' <"$PAYLOAD/contexts.txt" >"$W/contexts.clean"
else
  : >"$W/contexts.clean"
fi

# shellcheck disable=SC2086  # E2FS_PKGS is a space-separated package list
apk add --no-cache $E2FS_PKGS >/dev/null
echo "e2fsprogs: $(dumpe2fs -V 2>&1 | head -1)"

if [ "$HAS_AVB" = 1 ]; then
  echo "== avb footer"
  apk add --no-cache "$PYTHON3_PKG" >/dev/null
  [ -s "$AVBTOOL" ] || die "avbtool not visible in the container ($AVBTOOL); $HINT"
  python3 /container/avb-footer.py save "$AVBTOOL" "$IMG" "$W/avb.json" || die "AVB footer: cannot handle this image"
fi

# Default labels by path. contexts.txt line is "path context [mode]";
# path is an image path ("/system/bin/x") or a dir prefix ending in "/". First match wins.
default_ctx() {
  case "$1" in
    /system/lib/*|/system/lib64/*) echo u:object_r:system_lib_file:s0 ;;
    *) echo u:object_r:system_file:s0 ;;
  esac
}
lookup() { # lookup <path> <field 2|3>
  awk -v p="$1" -v f="$2" '
    /^[ \t]*(#|$)/ { next }
    { k=$1; if (k==p || (substr(k,length(k),1)=="/" && index(p,k)==1)) { print $f; exit } }' "$W/contexts.clean"
}
ctx_for() { c=$(lookup "$1" 2); if [ -n "$c" ]; then echo "$c"; else default_ctx "$1"; fi; }
mode4() { m=$1; while [ ${#m} -lt 4 ]; do m=0$m; done; echo "$m"; }

exists() { debugfs -R "stat $1" "$IMG" 2>/dev/null | grep -q '^Inode:'; }
info() { # info <path> -> "type mode4 uid gid", empty if absent
  debugfs -R "stat $1" "$IMG" 2>/dev/null | awk '
    /^Inode:/ { for (i = 1; i <= NF; i++) { if ($i == "Type:") t = $(i+1); if ($i == "Mode:") m = $(i+1) } }
    /^User:/ { u = $2; for (i = 1; i <= NF; i++) if ($i == "Group:") g = $(i+1) }
    END { if (t != "") { while (length(m) < 4) m = "0" m; print t, m, u, g } }'
}
getctx() { debugfs -R "ea_get $1 security.selinux" "$IMG" 2>/dev/null | sed -n 's/.*= "\(.*\)\\000"$/\1/p'; }
sibling_ctx() { # label of the first labelled regular file in <dir>, in debugfs ls order
  debugfs -R "ls -p $1" "$IMG" 2>/dev/null \
    | awk -F/ '$3 ~ /^100/ && $6 != "." && $6 != ".." && $6 !~ /[ \t]/ { print $6 }' \
    | while read -r n; do
        c=$(getctx "${1%/}/$n")
        if [ -n "$c" ]; then echo "$c"; break; fi
      done
  return 0
}

echo "== precheck"
feat=$(dumpe2fs -h "$IMG" 2>/dev/null | grep '^Filesystem features:' || true)
echo "$feat"
case " $feat " in
  *" shared_blocks "*) die "image has the shared_blocks feature: files share blocks, and rm could free blocks other files still use. Refusing to patch." ;;
esac
rc=0
e2fsck -fn "$IMG" >"$W/pre.log" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then cat "$W/pre.log"; die "input image is not clean (e2fsck -fn rc=$rc); not repairing it silently"; fi
tail -1 "$W/pre.log"

payload_bytes=0
while IFS= read -r f; do
  s=$(wc -c <"$PAYLOAD$f"); payload_bytes=$((payload_bytes + s))
done <"$W/files"
if [ "$have_append" -eq 1 ]; then
  payload_bytes=$((payload_bytes + $(wc -c <"$PAYLOAD/build.prop.append")))
fi

echo "== grow"
cur=$(wc -c <"$IMG")
# 2x payload (block rounding, dir blocks) + margin, rounded up to 4096.
want=$(( cur + 2 * payload_bytes + MARGIN_MIB * 1048576 ))
want=$(( (want + 4095) / 4096 * 4096 ))
truncate -s "$want" "$IMG"
# The image just passed e2fsck -fn, so this -fy has nothing to repair; resize2fs wants a fresh check.
rc=0; e2fsck -fy "$IMG" >"$W/pre2.log" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then cat "$W/pre2.log"; die "e2fsck before resize failed (rc=$rc)"; fi
resize2fs "$IMG" >"$W/resize.log" 2>&1 || { cat "$W/resize.log"; exit 1; }
grep . "$W/resize.log" | tail -1 || true
echo "image: $cur -> $want bytes"
free_inodes=$(dumpe2fs -h "$IMG" 2>/dev/null | awk '/^Free inodes:/ {print $3}')
need_inodes=$((nfiles + 64))
if [ "$free_inodes" -lt "$need_inodes" ]; then
  die "$free_inodes free inodes, need >= $need_inodes (raise MARGIN_MIB)"
fi
echo "free inodes: $free_inodes"

echo "== inject"
: >"$W/cmds"; : >"$W/summary"; : >"$W/dirs.done"; : >"$W/rec"
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
  mkdirs "$(dirname "$f")"
  dir=$(dirname "$f")
  table=$(default_ctx "$f")
  ov_ctx=$(lookup "$f" 2); ov_mode=$(lookup "$f" 3)
  ctx=""; src=table; mode=0644; uid=0; gid=0
  if exists "$f"; then
    case "$f" in
      */etc/selinux/product_sepolicy.cil|*/etc/selinux/product_file_contexts)
        # The pack replaces these whole because the GSI ships them empty; never drop a GSI's own product policy.
        debugfs -R "dump $f $W/old" "$IMG" >/dev/null 2>&1
        if grep -q '[^[:space:]]' "$W/old"; then
          die "$f in the image is not empty; replacing it would drop the GSI's own product policy. Merge it by hand."
        fi ;;
    esac
    # Replacing: keep the old label, mode and owner unless contexts.txt says otherwise.
    # shellcheck disable=SC2046  # intentional split into fields
    set -- $(info "$f")
    if [ "${1:-}" = regular ]; then
      old=$(getctx "$f"); mode=$2; uid=$3; gid=$4
      if [ -n "$old" ]; then ctx=$old; src=existing; fi
    fi
    echo "rm $f" >>"$W/cmds"
  elif exists "$dir"; then
    sib=$(sibling_ctx "$dir")
    if [ -n "$sib" ]; then ctx=$sib; src=sibling; fi
  fi
  if [ -n "$ov_ctx" ]; then ctx=$ov_ctx; src=contexts; fi
  if [ -n "$ov_mode" ]; then mode=$(mode4 "$ov_mode"); fi
  if [ -z "$ctx" ]; then ctx=$table; fi
  if [ "$ctx" != "$table" ]; then
    echo "note: $f label $ctx (from $src) differs from table default $table"
  fi
  {
    echo "write $PAYLOAD$f $f"
    echo "set_inode_field $f mode 010$mode"
    echo "set_inode_field $f uid $uid"
    echo "set_inode_field $f gid $gid"
    echo "ea_set -f $(mkctx "$ctx") $f security.selinux"
  } >>"$W/cmds"
  echo "$f $ctx $mode $uid $gid" >>"$W/rec"
  echo "file   $f  mode=$mode uid=$uid gid=$gid ctx=$ctx ($src)" >>"$W/summary"
  n=$((n + 1))
done <"$W/files"

bp_note=""
if [ "$have_append" -eq 1 ]; then
  exists "$BUILD_PROP_PATH" || die "$BUILD_PROP_PATH not in image"
  # shellcheck disable=SC2046
  set -- $(info "$BUILD_PROP_PATH")
  [ "${1:-}" = regular ] || die "$BUILD_PROP_PATH is not a regular file in the image"
  bpmode=$2; bpuid=$3; bpgid=$4
  bpold=$(getctx "$BUILD_PROP_PATH")
  bpctx=$(lookup "$BUILD_PROP_PATH" 2)
  if [ -z "$bpctx" ]; then bpctx=$bpold; fi
  if [ -z "$bpctx" ]; then bpctx=$(default_ctx "$BUILD_PROP_PATH"); fi
  if [ "$bpctx" != "$(default_ctx "$BUILD_PROP_PATH")" ]; then
    echo "note: $BUILD_PROP_PATH label $bpctx differs from table default $(default_ctx "$BUILD_PROP_PATH")"
  fi
  debugfs -R "dump $BUILD_PROP_PATH $W/build.prop.orig" "$IMG" >/dev/null 2>&1
  tr -d '\r' <"$PAYLOAD/build.prop.append" >"$W/append.clean"
  if [ -n "$(tail -c1 "$W/append.clean")" ]; then echo >>"$W/append.clean"; fi
  # init keeps the FIRST value of a ro.* property, so appending a duplicate is a silent no-op.
  while IFS= read -r line; do
    case "$line" in *=*) ;; *) continue ;; esac
    key=$(printf '%s' "${line%%=*}" | tr -d ' \t')
    case "$key" in ''|'#'*) continue ;; esac
    if awk -F= -v k="$key" '{ x = $1; gsub(/[ \t]/, "", x); if (x == k) f = 1 } END { exit !f }' "$W/build.prop.orig"; then
      case "$key" in
        ro.*) die "build.prop.append sets $key, which is already in $BUILD_PROP_PATH; init keeps the first ro.* value, so the append would silently do nothing. Remove it from the append (or patch the existing line some other way)." ;;
        *) echo "warning: $key is already in $BUILD_PROP_PATH; the later (appended) value wins" ;;
      esac
    fi
  done <"$W/append.clean"
  cp "$W/build.prop.orig" "$W/build.prop.new"
  if [ -n "$(tail -c1 "$W/build.prop.new")" ]; then echo >>"$W/build.prop.new"; fi
  cat "$W/append.clean" >>"$W/build.prop.new"
  {
    echo "rm $BUILD_PROP_PATH"
    echo "write $W/build.prop.new $BUILD_PROP_PATH"
    echo "set_inode_field $BUILD_PROP_PATH mode 010$bpmode"
    echo "set_inode_field $BUILD_PROP_PATH uid $bpuid"
    echo "set_inode_field $BUILD_PROP_PATH gid $bpgid"
    echo "ea_set -f $(mkctx "$bpctx") $BUILD_PROP_PATH security.selinux"
  } >>"$W/cmds"
  nl=$(grep -c '^[^#[:space:]]' "$W/append.clean" || true)
  bp_note="$nl line(s) appended to $BUILD_PROP_PATH (mode $bpmode, label $bpctx)"
  echo "append $BUILD_PROP_PATH  $bp_note" >>"$W/summary"
fi

debugfs -w -f "$W/cmds" "$IMG" >"$W/dbg.log" 2>&1 || true
# debugfs echoes each command ("debugfs: ...") then any error text; flag anything else.
if grep -Ev '^debugfs [0-9]|^debugfs: |^Allocated inode: |^$' "$W/dbg.log" | grep -q .; then
  grep -Ev '^debugfs [0-9]|^debugfs: |^Allocated inode: |^$' "$W/dbg.log"
  die "debugfs reported problems"
fi

echo "== verify"
chk_meta() { # chk_meta <path> <ctx> <mode4> <uid> <gid>
  got=$(getctx "$1")
  [ "$got" = "$2" ] || die "selinux label mismatch on $1: '$got' (want $2)"
  got=$(info "$1")
  [ "$got" = "regular $3 $4 $5" ] || die "mode/owner mismatch on $1: '$got' (want 'regular $3 $4 $5')"
}
while read -r f ctx mode uid gid; do
  debugfs -R "dump $f $W/chk" "$IMG" >/dev/null 2>&1
  cmp -s "$PAYLOAD$f" "$W/chk" || die "content mismatch: $f"
  chk_meta "$f" "$ctx" "$mode" "$uid" "$gid"
done <"$W/rec"
if [ "$have_append" -eq 1 ]; then
  debugfs -R "dump $BUILD_PROP_PATH $W/chk" "$IMG" >/dev/null 2>&1
  cmp -s "$W/chk" "$W/build.prop.new" || die "build.prop mismatch"
  chk_meta "$BUILD_PROP_PATH" "$bpctx" "$bpmode" "$bpuid" "$bpgid"
fi
e2fsck -fn "$IMG" >"$W/post.log" 2>&1 || { cat "$W/post.log"; die "e2fsck -fn not clean after patch"; }
tail -1 "$W/post.log"

if [ "$HAS_AVB" = 1 ]; then
  echo "== avb footer"
  python3 /container/avb-footer.py restore "$AVBTOOL" "$IMG" "$W/avb.json" || die "AVB footer: adding the new footer failed"
fi

echo "== summary"
cat "$W/summary"
echo "injected $n file(s)"
if [ -n "$bp_note" ]; then echo "$bp_note"; fi
