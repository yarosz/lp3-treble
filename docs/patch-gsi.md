# patch-gsi.sh reference

`scripts/patch-gsi.sh` writes a payload tree into a raw ext4 GSI `system.img`, offline. It runs e2fsprogs
1.47.0 in a pinned `alpine:3.20` container. Versions are in `scripts/lib.sh`.

```
scripts/patch-gsi.sh <in system.img> <out system.img> <payload dir>
```

## Inputs and output

- The input image is copied to the output and never modified.
- The input must be raw ext4 (not sparse), pass `e2fsck -fn`, and not have the `shared_blocks` feature. The
  patcher never repairs an input.
- The output is grown by twice the payload size plus `MARGIN_MIB` (default 256), which also adds inodes. It
  is checked with `e2fsck -fn` after patching.
- The input, the output directory and the payload must be under `$HOME`, the only path colima mounts by
  default. To use another path, add a colima mount and list it in `LP3_TREBLE_SHARED_ROOTS`
  (colon-separated).
- Each run needs network for `apk`.

## Payload layout

The payload directory mirrors the image root:

| Payload path | Goes to |
|---|---|
| `system/product/overlay/x.apk` | `/system/product/overlay/x.apk` |
| `system/etc/permissions/x.xml` | `/system/etc/permissions/x.xml` |
| `build.prop.append` | Lines appended to a fresh copy of `BUILD_PROP_PATH` |
| `contexts.txt` | Label and mode overrides (see below) |

Payload entries must be regular files. The patcher skips `.DS_Store` and `._*` files and refuses symlinks
and paths with whitespace.

## Labels, modes and owners

A new file gets uid 0, gid 0, mode 0644, and the first label that applies:

1. Its line in `contexts.txt`.
2. The label of a regular file already in the same image directory.
3. The default from this table.

| Path | Default `security.selinux` |
|---|---|
| `/system/lib/*`, `/system/lib64/*` | `u:object_r:system_lib_file:s0` |
| Everything else | `u:object_r:system_file:s0` |

A file that replaces an existing one keeps the old label, mode, uid and gid, unless `contexts.txt` sets
them. New directories get mode 0755 and the default label. The patcher prints a line whenever the label it
chose differs from the default.

`contexts.txt` has one `path context [mode]` per line. The path is a file or a directory prefix that ends in
`/`. The label must match `u:object_r:<type>:s0`. The mode is 3 octal digits, and setuid, setgid and sticky
bits are rejected. The patcher checks every line before it copies the image.

```
/system/bin/foo  u:object_r:system_file:s0  0755
```

The patcher refuses to replace `/system/product/etc/selinux/product_sepolicy.cil` or `product_file_contexts`
if the image's copy is not empty.

## build.prop.append

`BUILD_PROP_PATH` defaults to `/system/build.prop`. The LP3 props in `props/product.prop` go to
`/system/product/etc/build.prop`, because product props load after the vendor's and override them.

The target file keeps its mode, owner and label. If an appended key that starts with `ro.` is already in
the target file, the patcher stops. Other duplicate keys print a warning.

## AVB footer

GSI images end in an AVB hashtree footer with forward error correction (FEC). DSU verifies the image
through that footer, and FEC repairs every changed block back to stock at boot. If the input has a footer,
the patcher removes it before patching and adds a new one after:

- Kept: partition name, hash algorithm, block size, salt, rollback index and its location, header flags, and
  properties.
- Changed: no FEC, and no signature (algorithm `NONE`). DSU accepts an unsigned image only on an unlocked
  bootloader. The patcher can't check the bootloader state.
- Refused: footers with any descriptor other than one hashtree descriptor and properties.

The tool is AOSP's `avbtool.py` (Apache-2.0) from `platform/external/avb` at a pinned commit (tag
`android-16.0.0_r1`). It is downloaded on first use, checked against a pinned sha256, and cached in
`~/.cache/lp3-treble/`. To use a local copy with the same hash, set `LP3_TREBLE_AVBTOOL`.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `MARGIN_MIB` | 256 | Extra space added to the image |
| `BUILD_PROP_PATH` | `/system/build.prop` | File that `build.prop.append` extends |
| `LP3_TREBLE_SHARED_ROOTS` | `$HOME` | Paths the container VM can see |
| `LP3_TREBLE_AVBTOOL` | | Local `avbtool.py` to use instead of the download |
| `LP3_TREBLE_CACHE` | `~/.cache/lp3-treble` | Download cache |
| `ALPINE_IMAGE`, `E2FSPROGS_PKG`, `E2FSPROGS_EXTRA_PKG`, `PYTHON3_PKG` | see `scripts/lib.sh` | Pinned container and packages |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Patched |
| 64 | Usage or input error |
| 69 | docker unavailable |
| 1 | Patch failed. The output file is removed. |

## Self-test

`scripts/test-patch-gsi.sh` builds a throwaway 160 MiB GSI-shaped image, with and without an AVB footer, and
checks the patcher's output and refusals. It needs docker, and network on the first run.
