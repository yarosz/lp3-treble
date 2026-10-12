#!/usr/bin/env bash
# Shared settings for the image tools. Source it; do not run it.
# The container image is pinned by tag; e2fsprogs is pinned to the version that tag ships.
# Override both together if you move to another Alpine release.
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:3.20}"
E2FSPROGS_PKG="${E2FSPROGS_PKG:-e2fsprogs=1.47.0-r5}"
E2FSPROGS_EXTRA_PKG="${E2FSPROGS_EXTRA_PKG:-e2fsprogs-extra=1.47.0-r5}"

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

need_docker() {
  command -v docker >/dev/null 2>&1 || { echo "error: docker not found (start colima or Docker Desktop)" >&2; exit 69; }
  docker info >/dev/null 2>&1 || { echo "error: docker daemon not reachable (try: colima start)" >&2; exit 69; }
}
