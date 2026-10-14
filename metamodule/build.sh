#!/usr/bin/env bash
# Builds out/meta-overlayfs-<version>.zip: KernelSU's meta-overlayfs metamodule from its last in-tree source
# (tiann/KernelSU 926f64d3), with metamodule/meta-overlayfs.patch applied, as a static arm64 binary. Needs docker
# and network. Nothing touches a device. Usage: metamodule/build.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
commit=926f64d3c8b6fcd4c9aabdaa77f893a1486d2d73
tar_sha256=9e9bc6940382b4db4ea9c2a8a00ff5ef048c9d8d166af9ed0b3ff862ee1278d5
# Under the repo, not mktemp: colima shares only $HOME with docker.
mkdir -p "$root/out"
work=$(mktemp -d "$root/out/metamodule-build.XXXXXX")
trap 'rm -rf "$work"' EXIT

curl -fsSL "https://codeload.github.com/tiann/KernelSU/tar.gz/$commit" -o "$work/src.tar.gz"
echo "$tar_sha256  $work/src.tar.gz" | shasum -a 256 -c - >/dev/null || { echo "source tarball hash mismatch" >&2; exit 1; }
mkdir "$work/src"
tar -xzf "$work/src.tar.gz" -C "$work/src" --strip-components=3 "KernelSU-$commit/userspace/meta-overlayfs"
patch -s -d "$work/src" -p1 < "$root/metamodule/meta-overlayfs.patch"
cp "$root/metamodule/Cargo.lock" "$work/src/Cargo.lock"
version=$(sed -n 's/^version=//p' "$work/src/metamodule/module.prop")

mkdir -p "$work/out"
docker run --rm -v "$work/src":/src:ro -v "$work/out":/out rust:1.89-alpine sh -euc '
  apk add -q --no-cache musl-dev git zip >/dev/null
  cp -r /src /build && cd /build
  cargo build --release --locked --target aarch64-unknown-linux-musl
  mkdir /out/module
  cp target/aarch64-unknown-linux-musl/release/meta-overlayfs /out/module/meta-overlayfs-aarch64
  cp metamodule/module.prop metamodule/*.sh /out/module/
  chmod 755 /out/module/*.sh /out/module/meta-overlayfs-aarch64
  cd /out/module && zip -qrX ../meta-overlayfs.zip .
'
zip="$root/out/meta-overlayfs-$version.zip"
cp "$work/out/meta-overlayfs.zip" "$zip"
echo "BUILT $zip"
shasum -a 256 "$zip" "$work/out/module/meta-overlayfs-aarch64"
