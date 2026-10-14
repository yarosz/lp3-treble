# meta-overlayfs (KernelSU metamodule)

KernelSU doesn't mount a module's `system/` files by itself: it needs a mounting metamodule. lp3-treble's
module ships overlays and keylayouts there, so on KernelSU (including ReSukiSU, which vandamd/light-guide
installs) it needs one. This directory builds KernelSU's own reference metamodule, meta-overlayfs, with a small
patch.

## Source

- KernelSU's meta-overlayfs, `userspace/meta-overlayfs` at tiann/KernelSU commit `926f64d3`, the last commit
  before it moved to the KernelSU-Modules-Repo organization. That repo, and the release asset its
  `update.json` pointed to, weren't publicly reachable when this was written (2026-10-14).
- License: GPL-3.0 (KernelSU's). `meta-overlayfs.patch` is a derivative of it and is GPL-3.0 too. The rest of
  lp3-treble stays Apache-2.0.

## What the patch changes

1. `Cargo.toml`: uses `rustix` 1.x from crates.io instead of a KernelSU fork that is no longer reachable, and
   pins `hole-punch` to a commit. `Cargo.lock` here pins every dependency.
2. `src/mount.rs`: one call adapted to the `rustix` 1.x `mount()` signature.
3. `metamount.sh`, `metainstall.sh`: label `modules.img` `ksu_file` before mounting it. KernelSU labels module
   directories `system_file`, and ReSukiSU's SELinux policy denies the loop device writes to that type, so
   the mount fails with an I/O error.
4. `module.prop`: version `1.1.0-lp3treble.1`, no `updateJson` (the upstream one points to a missing file).

## Build

`metamodule/build.sh` (docker and network; nothing touches a device) downloads the source tarball, checks its
sha256, applies the patch and builds a static arm64 binary into `out/meta-overlayfs-<version>.zip`. Repeated
builds produce the same binary.

## Install

From the KernelSU (or ReSukiSU) app, or `ksud module install`: the metamodule first, reboot, then the
lp3-treble module, reboot. A module installed before the metamodule must be installed again. See
[`docs/module.md`](../docs/module.md).
