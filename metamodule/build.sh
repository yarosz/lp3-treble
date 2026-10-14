#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds out/meta-overlayfs-<version>.zip and out/meta-overlayfs-<version>-source.tar.gz: KernelSU's meta-overlayfs
# metamodule from its last in-tree source (tiann/KernelSU 926f64d3), with metamodule/meta-overlayfs.patch applied,
# as a static arm64 (musl) binary. Needs docker on an arm64 host (or one that can run linux/arm64 images) and
# network. Nothing touches a device. Usage: metamodule/build.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
commit=926f64d3c8b6fcd4c9aabdaa77f893a1486d2d73
tar_sha256=9e9bc6940382b4db4ea9c2a8a00ff5ef048c9d8d166af9ed0b3ff862ee1278d5
image=rust:1.89-alpine@sha256:4b800f2e72e04be908e5f634c504c741bd943b763d1d8ad7b096cc340e1b5b46
# File times inside the zip (2026-10-14 00:00 UTC), so the zip is byte-identical across builds.
epoch=1791936000
# Under the repo, not mktemp's default: colima shares only $HOME with docker.
mkdir -p "$root/out"
work=$(mktemp -d "$root/out/metamodule-build.XXXXXX")
trap 'rm -rf "$work"' EXIT

(cd "$work" && curl -fsSL "https://codeload.github.com/tiann/KernelSU/tar.gz/$commit" -o src.tar.gz &&
  echo "$tar_sha256  src.tar.gz" | shasum -a 256 -c - >/dev/null) || { echo "source download or hash check failed" >&2; exit 1; }
mkdir "$work/src"
tar -xzf "$work/src.tar.gz" -C "$work/src" --strip-components=3 "KernelSU-$commit/userspace/meta-overlayfs"
patch -s -d "$work/src" -p1 < "$root/metamodule/meta-overlayfs.patch"
cp "$root/metamodule/Cargo.lock" "$work/src/Cargo.lock"
version=$(sed -n 's/^version=//p' "$work/src/metamodule/module.prop")

# The zip carries the license and where the source is (GPL-3.0 sections 4 and 6).
mkdir -p "$work/out/module"
cp "$root/metamodule/LICENSE" "$work/out/module/LICENSE"
cat >"$work/out/module/SOURCE.txt" <<EOF
meta-overlayfs $version (lp3-treble build). Unofficial: not built or supported by the KernelSU developers.
License: GNU GPL version 3 (LICENSE). Binary: static aarch64 musl.
Source: tiann/KernelSU commit $commit, userspace/meta-overlayfs (tarball sha256 $tar_sha256),
with metamodule/meta-overlayfs.patch and metamodule/Cargo.lock from https://github.com/yarosz/lp3-treble.
The complete source is also attached to each lp3-treble release that ships this zip
(meta-overlayfs-$version-source.tar.gz). Build: metamodule/build.sh.
EOF

docker run --rm --platform linux/arm64 -e EPOCH="$epoch" -e OWNER="$(id -u):$(id -g)" \
  -v "$work/src":/src:ro -v "$work/out":/out "$image" sh -euc '
  apk add -q --no-cache musl-dev git zip >/dev/null
  cp -r /src /build && cd /build
  cargo build --release --locked --target aarch64-unknown-linux-musl
  cp target/aarch64-unknown-linux-musl/release/meta-overlayfs /out/module/meta-overlayfs-aarch64
  cp metamodule/module.prop metamodule/*.sh /out/module/
  chmod 755 /out/module/*.sh /out/module/meta-overlayfs-aarch64
  chmod 644 /out/module/module.prop /out/module/LICENSE /out/module/SOURCE.txt
  find /out/module -exec touch -d "@$EPOCH" {} +
  cd /out/module && ls -A | LC_ALL=C sort | zip -qX ../meta-overlayfs.zip -@
  chown -R "$OWNER" /out
'
zip="$root/out/meta-overlayfs-$version.zip"
src="$root/out/meta-overlayfs-$version-source.tar.gz"
cp "$work/out/meta-overlayfs.zip" "$zip"
(cd "$work" && cp "$root/metamodule/meta-overlayfs.patch" "$root/metamodule/Cargo.lock" "$root/metamodule/LICENSE" src/ &&
  tar --uid 0 --gid 0 --numeric-owner -czf "$src" -C src .)
echo "BUILT $zip"
echo "BUILT $src"
echo "binary sha256 $(shasum -a 256 "$work/out/module/meta-overlayfs-aarch64" | cut -d' ' -f1)"
shasum -a 256 "$zip"
