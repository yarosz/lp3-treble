# lp3-treble

System-side configuration for running a generic Android Treble GSI on the Light Phone III (TLP301,
Qualcomm SM4450 "parrot"): runtime resource overlays, props and keylayouts, packaged for a patched GSI
image and, later, as a KernelSU/Magisk module. It installs on top of the stock vendor and kernel and
changes neither.

First target: the unofficial LineageOS GSI by MisterZtr ([MisterZtr/LineageOS_gsi](https://github.com/MisterZtr/LineageOS_gsi)).

**Status: work in progress, nothing to install yet.** Progress is in [`LEDGER.md`](LEDGER.md).

> Unaffiliated with Light. "Light Phone" is Light's trademark. This project is not endorsed by Light,
> LineageOS or any GSI maintainer. For the LineageOS GSI (unofficial). Unlocking and flashing can lose
> data or brick a device; you do it at your own risk.

## Scope of the first preview

- Calls (VoLTE), SMS, MMS and mobile data, tested per carrier.
- Fingerprint unlock and BiometricPrompt.
- Passkeys through a third-party credential provider (`android.software.credentials`).
- LP3 keys (scroll wheel, shutter, HOME) and display size.
- Install and clean uninstall, via Dynamic System Updates (DSU) and via full flash.

Not in scope: camera, NFC, Light's own Tools on the GSI, eSIM management, Wi-Fi Calling, building a
kernel or any Android image. This repo ships overlays and props only, never vendor blobs or Light's
proprietary files.

## Build a patched image

Needs docker (colima is fine) and a raw ext4 GSI `system.img` you downloaded yourself; no e2fsprogs on the
host. The tools run e2fsprogs 1.47.0 in a pinned `alpine:3.20` container (versions in `scripts/lib.sh`),
which needs network for `apk` on each run. Nothing is mounted and no device is touched.

GSI images end in an AVB hashtree footer with forward error correction (FEC). DSU verifies the image
through it, and FEC silently "repairs" every patched block back to stock at boot, so a naively patched image
boots unpatched. `patch-gsi.sh` erases that footer before patching and adds a fresh one after: same partition
name, hash algorithm, salt, rollback index and properties, no FEC, unsigned (algorithm NONE, which DSU
accepts on an unlocked bootloader; on a locked one the install or boot fails, which the patcher can't check). It refuses footers carrying anything else (hash or chain descriptors,
kernel command lines). The tool is AOSP's `avbtool.py` (Apache-2.0), fetched on first use from
`platform/external/avb` at a pinned commit (tag `android-16.0.0_r1`), checked against a pinned sha256 and
cached in `~/.cache/lp3-treble/`; set `LP3_TREBLE_AVBTOOL` to use a local copy (same hash).

```
scripts/patch-gsi.sh system.img patched.img payload/
scripts/pack-dsu.sh patched.img patched.img.gz     # prints the DSU adb commands, runs nothing
scripts/test-patch-gsi.sh                          # self-test on a throwaway 160 MiB GSI-shaped image (with and without an AVB footer)
```

`payload/` mirrors the image root, for example `payload/system/product/overlay/treble-overlay-lp3.apk`.
`scripts/build-overlays.sh` builds each `overlays/<name>/` into `out/overlays/lp3-treble-<name>.apk` (Android SDK
build-tools and the android-36 platform needed); copy those into `payload/system/product/overlay/`.
`props/product.prop` holds the LP3 props (display density, default network mode): use it as
`payload/build.prop.append` with `BUILD_PROP_PATH=/system/product/etc/build.prop`, because product props load
after the vendor's and win. The `ims-caf` and `ims-caf-framework` overlays name the Qualcomm IMS app as the
device's IMS service and mark the device VoLTE-capable from the first boot. phh's equivalents only switch on after
a boot, through the Treble app, so VoLTE came up only on the second boot after installing the IMS app. Without the
IMS app installed, nothing binds and calls stay on the normal path.
`scripts/build-atel.sh` builds `lp3-atel-ready`, the fix for incoming SMS lost while the screen is off
([`atel/README.md`](atel/README.md)), and stages it under `out/atel/payload/`: merge that tree into your
payload and append its `contexts.txt` lines to yours. Before installing a new GSI build, run
`scripts/check-sepolicy.sh` (see `atel/README.md`): a product policy that doesn't compile stops the GSI booting.
Optional `payload/build.prop.append` lines go into a fresh copy of `/system/build.prop`. The input image is
never modified; the output is grown by twice the payload plus 256 MiB (`MARGIN_MIB`, which also adds
inodes), then checked with `e2fsck -fn`. The input must pass `e2fsck -fn` first (it is never auto-repaired)
and must not have `shared_blocks`. Input, output dir and payload must live under `$HOME`, the only path
colima mounts by default (else add a mount and list it in `LP3_TREBLE_SHARED_ROOTS`, colon-separated).
Payload entries must be regular files; `.DS_Store` and `._*` are skipped, symlinks refused.

A new file gets uid/gid 0, mode 0644 and the first match of: `contexts.txt`; the label of a regular file
already in the same image directory; the table below. A file that replaces an existing one keeps its
old label, mode and uid/gid unless `contexts.txt` overrides. `build.prop` keeps mode, owner and label.
New directories get 0755 and the table label. A line is printed whenever the chosen label differs from the table.

| Path | table default `security.selinux` |
|---|---|
| `/system/lib/*`, `/system/lib64/*` | `u:object_r:system_lib_file:s0` |
| everything else (overlays, permission XMLs, keylayouts, props) | `u:object_r:system_file:s0` |

`payload/contexts.txt`: one `path context [mode]` per line (path or a dir prefix ending in `/`). Labels must
match `u:object_r:<type>:s0`, modes are 3 octal digits (setuid/setgid/sticky rejected), all checked up front:

```
/system/bin/foo  u:object_r:system_file:s0  0755
```

`build.prop.append` keys that already exist in the image's `build.prop` fail if they start with `ro.`
(init keeps the first value, so the append would do nothing); other duplicates only warn.

## Contributing test results

A per-carrier test checklist comes with the first preview. Never paste IMEI, IMSI, ICCID, EID, phone
numbers, serial numbers, MAC addresses or account emails into an issue or log. A pre-push hook
(`.githooks/pre-push`, enable with `git config core.hooksPath .githooks`) rejects them in this repo.

## Credits

- **Vandam** for the LP3 bootloader unlock, installer and the
  [light-guide](https://github.com/vandamd/light-guide) GSI tweaks this builds on.
- **MisterZtr** for the LineageOS GSI.
- **phh (Pierre-Hugues Husson)** and the TrebleDroid project for the Treble GSI work and IMS patches.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
