#!/usr/bin/env bash
# Shared settings for the image tools. Source it; do not run it.
# The container image is pinned by tag; e2fsprogs is pinned to the version that tag ships.
# Override both together if you move to another Alpine release.
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:3.20}"
E2FSPROGS_PKG="${E2FSPROGS_PKG:-e2fsprogs=1.47.0-r5}"
E2FSPROGS_EXTRA_PKG="${E2FSPROGS_EXTRA_PKG:-e2fsprogs-extra=1.47.0-r5}"
PYTHON3_PKG="${PYTHON3_PKG:-python3=3.12.13-r0}"

# avbtool from AOSP platform/external/avb (Apache-2.0), pinned by commit (tag android-16.0.0_r1) and sha256.
# Fetched on first use into the cache; never vendored here. LP3_TREBLE_AVBTOOL points at a local copy instead
# (it must still match the hash).
AVBTOOL_COMMIT=5ac0c3a071d811846a62412383dd6e259f341e6e
AVBTOOL_SHA256=e5a664a38db623da00f080219bc0ee60a640a9dc4a872803616fae4938ac749b
AVBTOOL_URL="https://android.googlesource.com/platform/external/avb/+/$AVBTOOL_COMMIT/avbtool.py?format=TEXT"
CACHE_DIR="${LP3_TREBLE_CACHE:-$HOME/.cache/lp3-treble}"

abspath() { # abspath <existing dir>
  (cd "$1" && pwd -P)
}

# colima shares only $HOME with its VM; a docker bind mount of any other host path is an EMPTY
# directory inside the container. LP3_TREBLE_SHARED_ROOTS (colon-separated) overrides $HOME.
SHARED_ROOTS="${LP3_TREBLE_SHARED_ROOTS:-$HOME}"
under_shared() { # under_shared <abs path>
  _p=$1; _oldifs=$IFS; IFS=:
  # shellcheck disable=SC2086  # intentional split on ':'
  set -- $SHARED_ROOTS
  IFS=$_oldifs
  for _r in "$@"; do
    [ -n "$_r" ] || continue
    _rr=$(cd "$_r" 2>/dev/null && pwd -P) || continue
    _rr=${_rr%/}
    case "$_p" in "$_rr"|"$_rr"/*) return 0 ;; esac
  done
  return 1
}
require_shared() { # require_shared <label> <abs path>
  under_shared "$2" && return 0
  echo "error: $1 ($2) is not under a directory shared with the container VM ($SHARED_ROOTS)." >&2
  echo "       colima mounts only \$HOME by default, so docker would see an empty directory there." >&2
  echo "       Move it under \$HOME, or add a colima mount and list it in LP3_TREBLE_SHARED_ROOTS (colon-separated)." >&2
  exit 64
}

sha256_of() { # sha256_of <file>
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# fetch_avbtool: print the path of a hash-checked avbtool.py, downloading it into CACHE_DIR if needed.
fetch_avbtool() {
  local f=${LP3_TREBLE_AVBTOOL:-$CACHE_DIR/avbtool-$AVBTOOL_COMMIT.py} tmp
  if [ -n "${LP3_TREBLE_AVBTOOL:-}" ]; then
    [ -f "$f" ] || { echo "error: LP3_TREBLE_AVBTOOL not found: $f" >&2; return 1; }
    f=$(abspath "$(dirname "$f")")/$(basename "$f")
  elif [ ! -f "$f" ]; then
    mkdir -p "$CACHE_DIR"
    echo "fetch: avbtool.py at AOSP external/avb $AVBTOOL_COMMIT" >&2
    tmp=$(mktemp "$CACHE_DIR/avbtool.XXXXXX")
    # gitiles serves raw files base64-encoded; openssl decodes on every macOS and Linux.
    curl -fsSL "$AVBTOOL_URL" | openssl base64 -d -A >"$tmp" || { rm -f "$tmp"; echo "error: avbtool download failed" >&2; return 1; }
    mv "$tmp" "$f"
  fi
  local got
  got=$(sha256_of "$f")
  if [ "$got" != "$AVBTOOL_SHA256" ]; then
    echo "error: $f has sha256 $got, want $AVBTOOL_SHA256" >&2
    [ -n "${LP3_TREBLE_AVBTOOL:-}" ] || rm -f "$f"
    return 1
  fi
  echo "$f"
}

# has_avb_footer <image>: the AVB footer is the last 64 bytes and starts with "AVBf".
has_avb_footer() {
  [ "$(tail -c 64 "$1" | head -c 4)" = AVBf ]
}

need_docker() {
  command -v docker >/dev/null 2>&1 || { echo "error: docker not found (start colima or Docker Desktop)" >&2; exit 69; }
  docker info >/dev/null 2>&1 || { echo "error: docker daemon not reachable (try: colima start)" >&2; exit 69; }
}
