#!/usr/bin/env bash
# Inject a payload tree into a raw ext4 GSI system image, offline, without mounting.
# Runs e2fsprogs inside a pinned Alpine container, so the Mac needs only docker (colima).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

usage() {
  cat <<'USAGE'
Usage: patch-gsi.sh <in system.img> <out system.img> <payload dir>

Copies the input to the output (the input is never modified), grows the copy, injects the
payload and checks the result with e2fsck. The payload dir mirrors the image root:

  payload/system/product/overlay/treble-overlay-lp3.apk   -> /system/product/overlay/...
  payload/system/etc/permissions/x.xml                    -> /system/etc/permissions/x.xml
  payload/build.prop.append   (optional) lines appended to /system/build.prop in a fresh copy
  payload/contexts.txt        (optional) "path context [mode]" overrides, e.g.
                              /system/bin/foo  u:object_r:system_file:s0  0755

New files get uid/gid 0, mode 0644 and a label: contexts.txt, else the label of a regular file
already in that directory, else the table in README.md. A replaced file keeps its old label, mode
and uid/gid unless contexts.txt overrides. New directories get 0755. macOS junk (.DS_Store, ._*)
is skipped; symlinks and other non-regular files are refused.

Input, output dir and payload must be under $HOME (colima shares only that), or under a root in
LP3_TREBLE_SHARED_ROOTS (colon-separated).
Env: MARGIN_MIB (default 256) extra space; BUILD_PROP_PATH (default /system/build.prop);
     ALPINE_IMAGE, E2FSPROGS_PKG, E2FSPROGS_EXTRA_PKG (see scripts/lib.sh).
Exit: 0 ok, 64 usage, 69 docker unavailable, 1 failure.
USAGE
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac
if [ $# -ne 3 ]; then usage >&2; exit 64; fi
in=$1 out=$2 payload=$3

[ -f "$in" ] || { echo "error: input image not found: $in" >&2; exit 64; }
[ -d "$payload" ] || { echo "error: payload dir not found: $payload" >&2; exit 64; }
[ ! -e "$out" ] || { echo "error: output exists, refusing to overwrite: $out" >&2; exit 64; }
outdir=$(dirname "$out")
[ -d "$outdir" ] || { echo "error: output directory not found: $outdir" >&2; exit 64; }

in_abs=$(abspath "$(dirname "$in")")/$(basename "$in")
out_abs=$(abspath "$outdir")/$(basename "$out")
payload_abs=$(abspath "$payload")
[ "$in_abs" != "$out_abs" ] || { echo "error: input and output are the same file" >&2; exit 64; }

# ext4 magic 0xEF53 at byte 0x438: reject sparse or non-ext4 input early.
magic=$(dd if="$in_abs" bs=1 skip=1080 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$magic" = "53ef" ] || { echo "error: $in is not a raw ext4 image (sparse? run simg2img first)" >&2; exit 1; }

# colima mounts only $HOME: refuse early rather than patch an empty mount.
require_shared "input image" "$in_abs"
require_shared "output directory" "$(dirname "$out_abs")"
require_shared "payload dir" "$payload_abs"

# Payload hygiene. Same listing code as the container (container/payload-list.sh).
# shellcheck source-path=SCRIPTDIR source=container/payload-list.sh
. "$here/container/payload-list.sh"
special=$(payload_special "$payload_abs")
if [ -n "$special" ]; then
  echo "error: payload has entries that are not regular files or directories (symlink, fifo, device):" >&2
  # shellcheck disable=SC2001
  echo "$special" | sed 's/^/  /' >&2
  exit 64
fi
junk=$(payload_junk "$payload_abs")
if [ -n "$junk" ]; then
  # shellcheck disable=SC2001
  echo "$junk" | sed 's/^/note: skipping macOS junk file: /'
fi
if payload_files "$payload_abs" | grep -q '[[:space:]]'; then
  echo "error: whitespace in a payload path (unsupported)" >&2; exit 64
fi
if [ -f "$payload_abs/contexts.txt" ]; then
  awk -f "$here/container/validate-contexts.awk" "$payload_abs/contexts.txt" || exit 64
fi
payload_count=$(payload_files "$payload_abs" | wc -l | tr -d ' ')
payload_append=0
if [ -f "$payload_abs/build.prop.append" ]; then payload_append=1; fi
if [ "$payload_count" -eq 0 ] && [ "$payload_append" -eq 0 ]; then
  echo "error: nothing to inject: payload has no files and no build.prop.append: $payload" >&2
  exit 64
fi
echo "payload: $payload_count file(s), build.prop.append: $payload_append"

need_docker

# Arm the cleanup before the multi-GB copy so an interrupted or failed cp leaves nothing behind.
# shellcheck disable=SC2154  # rc is set inside the trap string
trap 'rc=$?; if [ $rc -ne 0 ]; then rm -f "$out_abs"; echo "patch failed; removed $out_abs" >&2; fi' EXIT
echo "copy: $in_abs -> $out_abs"
cp "$in_abs" "$out_abs"

# LP3_TREBLE_FORCE_PAYLOAD_COUNT is a test hook that fakes a host/container mismatch.
docker run --rm \
  -v "$(dirname "$out_abs"):/img" \
  -v "$payload_abs:/payload:ro" \
  -v "$here/container:/container:ro" \
  -e IMG_NAME="$(basename "$out_abs")" \
  -e MARGIN_MIB="${MARGIN_MIB:-256}" \
  -e BUILD_PROP_PATH="${BUILD_PROP_PATH:-/system/build.prop}" \
  -e PAYLOAD_COUNT="${LP3_TREBLE_FORCE_PAYLOAD_COUNT:-$payload_count}" \
  -e PAYLOAD_APPEND="$payload_append" \
  -e E2FS_PKGS="$E2FSPROGS_PKG $E2FSPROGS_EXTRA_PKG" \
  "$ALPINE_IMAGE" sh /container/patch.sh

echo "output: $out_abs ($(wc -c <"$out_abs" | tr -d ' ') bytes)"
