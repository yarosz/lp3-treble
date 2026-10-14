# meta-overlayfs (KernelSU metamodule)

KernelSU doesn't mount a module's `system/` files by itself: it needs a mounting metamodule. lp3-treble's
module ships overlays and keylayouts there, so on KernelSU (including ReSukiSU, which vandamd/light-guide
installs) it needs one. This directory builds KernelSU's own reference metamodule, meta-overlayfs, with a small
patch.

## Source

- KernelSU's meta-overlayfs, `userspace/meta-overlayfs` at tiann/KernelSU commit `926f64d3`, the last commit
  before it moved to the KernelSU-Modules-Repo organization. That repo, and the release asset its
  `update.json` pointed to, weren't publicly reachable when this was written (2026-10-14).
- License: GNU GPL version 3, as in KernelSU's `LICENSE` (copied here as [`LICENSE`](LICENSE)).
  `meta-overlayfs.patch` is a derivative and is under the same license. The rest of lp3-treble stays
  Apache-2.0.
- Unofficial: built by lp3-treble, not by or with the KernelSU developers, who don't support it.

## What the patch changes

1. `Cargo.toml`: uses `rustix` 1.x from crates.io instead of a KernelSU fork that is no longer reachable, and
   pins `hole-punch` to a commit. `Cargo.lock` here pins every dependency.
2. `src/mount.rs`: one call adapted to the `rustix` 1.x `mount()` signature.
3. `metamount.sh`, `metainstall.sh`: label `modules.img` `ksu_file` before mounting it. KernelSU labels module
   directories `system_file`, and ReSukiSU's SELinux policy denies the loop device writes to that type, so
   the mount fails with an I/O error.
4. `module.prop`: version `1.1.0-lp3treble.1`, no `updateJson` (the upstream one points to a missing file).

Unlike upstream, which builds bionic binaries for arm64 and x86_64 with the NDK, this builds one static musl
binary for arm64 only; installing it on an x86_64 device stops with "Binary not found".

## Build

`metamodule/build.sh` (docker on an arm64 host, and network; nothing touches a device) downloads the source
tarball, checks its sha256, applies the patch and builds in a digest-pinned `rust:1.89-alpine` image. It writes
`out/meta-overlayfs-<version>.zip` (with `LICENSE` and `SOURCE.txt` inside) and
`out/meta-overlayfs-<version>-source.tar.gz` (the patched source, `Cargo.lock` and `LICENSE`), which is
attached to every release that ships the zip. Two builds on 2026-10-14 gave the same zip and binary (binary
sha256 `cc66ae97cd6102511e39e049cb829a90878ec47071d02c3b60184e781dc0fe5e`, the binary that was tested).

## Install

From the KernelSU (or ReSukiSU) app, or `ksud module install`: the metamodule first, reboot, then the
lp3-treble module, reboot. A module installed before the metamodule must be installed again. Tested on fresh
DSU userdata with ReSukiSU only: not over an earlier meta-overlayfs install, and not on other KernelSU builds
(the `chcon` logs a line if it fails there). See
[`docs/module.md`](../docs/module.md).
