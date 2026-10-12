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

```
scripts/patch-gsi.sh system.img patched.img payload/
scripts/pack-dsu.sh patched.img patched.img.gz     # prints the DSU adb commands, runs nothing
scripts/test-patch-gsi.sh                          # self-test on a throwaway 64 MiB image
```

`payload/` mirrors the image root, for example `payload/system/product/overlay/treble-overlay-lp3.apk`.
Optional `payload/build.prop.append` lines go into a fresh copy of `/system/build.prop`. The input image is
never modified; the output is grown by twice the payload plus 256 MiB (`MARGIN_MIB`, which also adds
inodes), then checked with `e2fsck -fn`. Files get uid/gid 0 and mode 0644, new directories 0755.

| Path | `security.selinux` |
|---|---|
| `/system/lib/*`, `/system/lib64/*` | `u:object_r:system_lib_file:s0` |
| everything else (overlays, permission XMLs, keylayouts, props) | `u:object_r:system_file:s0` |

Override with `payload/contexts.txt`, one `path context [mode]` per line (path or a dir prefix ending in `/`):

```
/system/bin/foo  u:object_r:system_file:s0  0755
```

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
