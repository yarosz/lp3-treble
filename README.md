# lp3-treble

LP3-specific configuration for running a generic Android Treble GSI on the Light Phone III (TLP301,
Qualcomm SM4450 "parrot"). It ships overlays, props and one small helper, and goes into a patched GSI image
(later also a KernelSU or Magisk module). The stock vendor and kernel stay unchanged.

First target: the unofficial LineageOS GSI by MisterZtr ([MisterZtr/LineageOS_gsi](https://github.com/MisterZtr/LineageOS_gsi)).

**Status: work in progress, nothing to install yet.** Progress is in [`LEDGER.md`](LEDGER.md).

> Unaffiliated with Light. "Light Phone" is Light's trademark. This project is not endorsed by Light,
> LineageOS or any GSI maintainer. For the LineageOS GSI (unofficial). Unlocking and flashing can lose
> data or brick a device. You do it at your own risk.

## What's in the pack

| Part | What it fixes |
|---|---|
| [`atel/`](atel/README.md) (`lp3-atel-ready`) | Incoming SMS lost while the screen is off |
| `overlays/carrierconfig` | VoLTE off for AT&T SIMs (310/280, 310/410) |
| `overlays/ims-caf`, `overlays/ims-caf-framework` | VoLTE missing on the first boot after installing the IMS app ([why](docs/ims-overlays.md)) |
| `props/product.prop` | Display density (320) and LTE as the default network mode |

## Scope of the first preview

- Calls (VoLTE), SMS, MMS and mobile data, tested per carrier.
- Fingerprint unlock and BiometricPrompt.
- Passkeys through a third-party credential provider (`android.software.credentials`).
- LP3 keys (scroll wheel, shutter, HOME) and display size.
- Install and clean uninstall, via Dynamic System Updates (DSU) and via full flash.

Not in scope: camera, NFC, Light's own Tools on the GSI, eSIM management, Wi-Fi Calling, building a
kernel or any Android image. This repo ships only overlays, props and its own code, never vendor blobs or
Light's proprietary files.

## Build a test image

You need:

- docker (colima works). The tools run e2fsprogs and avbtool in a container, so the host needs neither.
- The Android SDK (build-tools and the android-36 platform) and a JDK.
- A raw ext4 GSI `system.img` that you downloaded and unpacked yourself.
- An LP3 with an unlocked bootloader, to boot the result through DSU.

1. Build the pack. The payload goes to `out/payload/`.

   ```
   scripts/build-payload.sh
   ```

2. Patch your GSI image. Your `system.img` is copied, never changed.

   ```
   BUILD_PROP_PATH=/system/product/etc/build.prop scripts/patch-gsi.sh system.img lp3.img out/payload
   ```

3. Compress the image and print the DSU install commands. The script runs no adb itself.

   ```
   scripts/pack-dsu.sh lp3.img lp3.img.gz
   ```

4. Run the printed `adb` commands. When the install finishes, boot the GSI once:

   ```
   adb shell gsi_tool enable --single-boot
   adb reboot
   ```

5. In the GSI, install the Qualcomm IMS app from phh's Treble settings (IMS section), then reboot once.

All options, label rules and the AVB footer handling are in the [`patch-gsi.sh` reference](docs/patch-gsi.md).
Before you use a new GSI build, run `scripts/check-sepolicy.sh` ([`atel/README.md`](atel/README.md)
explains why).

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
