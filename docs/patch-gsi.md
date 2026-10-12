# patch-gsi.sh reference

`scripts/patch-gsi.sh` writes a payload tree into a raw ext4 GSI `system.img`, offline. It runs e2fsprogs
1.47.0 in a pinned `alpine:3.20` container. `scripts/lib.sh` pins the versions.

```
scripts/patch-gsi.sh <in system.img> <out system.img> <payload dir>
```

## Inputs and output

- The patcher copies the input to the output and never modifies the input.
- The output must not exist yet, and its directory must exist.
- The input must be raw ext4 (not sparse), pass `e2fsck -fn`, and not have the `shared_blocks` feature. The
  patcher never repairs an input.
- The output grows by twice the payload size plus `MARGIN_MIB` (default 256). `resize2fs` adds inodes in
  proportion. If fewer than the payload's file count plus 64 inodes are free, the patch fails: raise
  `MARGIN_MIB`.
- The patcher checks the output with `e2fsck -fn` after patching.
- The input, the output directory, the payload and avbtool must be under a path the container VM shares.
  colima shares only `$HOME` by default. `LP3_TREBLE_SHARED_ROOTS` replaces that list, so include `$HOME`
  in it if you still need it.
- Each run needs network for `apk`, and the first run with an AVB footer needs it for avbtool.

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

A new file gets uid 0, gid 0, mode 0644, and the first label in this list that applies:

1. Its line in `contexts.txt`.
2. The label of a regular file already in the same image directory.
3. The default from this table.

| Path | Default `security.selinux` |
|---|---|
| `/system/lib/*`, `/system/lib64/*` | `u:object_r:system_lib_file:s0` |
| Everything else | `u:object_r:system_file:s0` |

A file that replaces an existing one keeps the old label, mode, uid and gid. `contexts.txt` can override
its label and mode, never its uid or gid. New directories get mode 0755, uid 0 and gid 0, and their label
comes from a `contexts.txt` directory prefix or the default. The patcher prints a line whenever the label it
chose differs from the default.

`contexts.txt` has one `path context [mode]` per line. The path is a file or a directory prefix that ends in
`/`. The label must match `u:object_r:<type>:s0`. The mode is 3 octal digits with an optional leading `0`.
The patcher rejects setuid, setgid and sticky bits. The patcher checks every line before it copies the image.

```
/system/bin/foo  u:object_r:system_file:s0  0755
```

The patcher refuses to replace any `etc/selinux/product_sepolicy.cil` or `etc/selinux/product_file_contexts`
whose copy in the image is not empty.

## build.prop.append

`BUILD_PROP_PATH` defaults to `/system/build.prop`. The LP3 props in `props/product.prop` go to
`/system/product/etc/build.prop`, because product props load after the vendor's and override them. On the
LP3, `ro.sf.lcd_density` set there replaced the vendor's 480 (`LEDGER.md`).

The target file keeps its mode and owner, and its label unless `contexts.txt` overrides it. If an appended key that starts with `ro.` is already in
the target file, the patcher stops. Other duplicate keys print a warning.

## AVB footer

GSI images end in an AVB hashtree footer with forward error correction (FEC). DSU verifies the image
through that footer. On the LP3, FEC repaired every changed block back to stock at boot (`LEDGER.md`). If the input has a footer,
the patcher removes it before patching and adds a new one after:

- Kept: partition name, hash algorithm, block size, salt, rollback index and its location, header flags, and
  properties.
- Changed: no FEC, and no signature (algorithm `NONE`). DSU accepts an unsigned image only on an unlocked
  bootloader. The patcher can't check the bootloader state.
- Refused: footers with any descriptor other than one hashtree descriptor and properties, hashtree flags
  other than 0, different data and hash block sizes, property keys that contain `:`, and property values
  that are not UTF-8.

The tool is AOSP's `avbtool.py` (Apache-2.0) from `platform/external/avb` at a pinned commit (tag
`android-16.0.0_r1`). The patcher downloads it on first use, checks it against a pinned sha256, and caches
it in `~/.cache/lp3-treble/`.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `MARGIN_MIB` | 256 | Extra space added to the image |
| `BUILD_PROP_PATH` | `/system/build.prop` | File that `build.prop.append` extends |
| `LP3_TREBLE_SHARED_ROOTS` | `$HOME` | Paths the container VM shares, colon-separated. Replaces the default. |
| `LP3_TREBLE_AVBTOOL` | | Local `avbtool.py` to use instead of the download. Must match the pinned sha256. |
| `LP3_TREBLE_CACHE` | `~/.cache/lp3-treble` | Download cache |
| `ALPINE_IMAGE`, `E2FSPROGS_PKG`, `E2FSPROGS_EXTRA_PKG`, `PYTHON3_PKG` | see `scripts/lib.sh` | Pinned container and packages |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | The image was patched. |
| 64 | Bad arguments or paths: missing files, an existing output, unshared paths, or an invalid payload. |
| 69 | docker is unavailable. |
| 1 | Any other failure, such as a sparse or unclean input or a refused AVB footer. The output file is removed. |

## Self-test

`scripts/test-patch-gsi.sh` builds a throwaway 160 MiB GSI-shaped image, with and without an AVB footer, and
checks the patcher's output and refusals. It needs docker, and network on the first run.
