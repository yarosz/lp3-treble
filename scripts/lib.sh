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

need_docker() {
  command -v docker >/dev/null 2>&1 || { echo "error: docker not found (start colima or Docker Desktop)" >&2; exit 69; }
  docker info >/dev/null 2>&1 || { echo "error: docker daemon not reachable (try: colima start)" >&2; exit 69; }
}
