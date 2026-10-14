# lp3-treble

LP3-specific configuration for running a generic Android Treble GSI on the Light Phone III (TLP301,
Qualcomm SM4450 "parrot"). The pack is a set of overlays, props and one small helper that you patch into a GSI
image. The stock vendor and kernel stay unchanged.

First target: the unofficial LineageOS GSI by MisterZtr ([MisterZtr/LineageOS_gsi](https://github.com/MisterZtr/LineageOS_gsi)).

**Status: early preview ([`v0.1.0-preview.1`](https://github.com/yarosz/lp3-treble/releases/tag/v0.1.0-preview.1)). You build the image yourself.** Progress is in
[`LEDGER.md`](LEDGER.md).

> Unaffiliated with Light. "Light Phone" is Light's trademark. This project is not endorsed by Light,
> LineageOS or any GSI maintainer. For the LineageOS GSI (unofficial). Unlocking and flashing can lose
> data or brick a device. You do it at your own risk.

## What's in the pack

| Part | What it does |
|---|---|
| [`atel/`](atel/README.md) (`lp3-atel-ready`) | Delivers incoming SMS while the screen is off |
| `overlays/carrierconfig` | Enables VoLTE for AT&T SIMs (310/280, 310/410) |
| `overlays/ims-caf`, `overlays/ims-caf-framework` | Brings up VoLTE on the first boot after you install the IMS app ([why](docs/ims-overlays.md)) |
| `overlays/framework` | Turns on auto-brightness, with stock LightOS's curve |
| `props/product.prop` | Sets display density 320 and NR/LTE/GSM/WCDMA as the default network mode |
| `keylayout/` | Maps the scroll wheel and the side keys (same mapping as vandamd/light-guide) |

The pack comes in two forms built from the same sources: a patched GSI image (below) and a KernelSU / Magisk
module for a rooted GSI ([module](docs/module.md)).

## Scope of the first preview

- Calls (VoLTE), SMS, MMS and mobile data, tested per carrier.
- Fingerprint unlock and BiometricPrompt.
- Passkeys through a third-party credential provider (`android.software.credentials`).
- LP3 keys (scroll wheel, shutter, HOME) and display size.
- Install and clean uninstall, via Dynamic System Updates (DSU) and via full flash.

Not in scope: Light's own Tools on the GSI, eSIM management, Wi-Fi Calling (an experimental overlay exists:
`overlays-experimental/wfc`, built with `LP3_EXPERIMENTAL=1`), building a
kernel or any Android image. This repo ships only overlays, props and its own code, never vendor blobs or
Light's proprietary files.

## Build a test image

You need:

- docker (colima works). The tools run e2fsprogs and avbtool in a container, so the host needs neither.
- The Android SDK (build-tools and the android-36 platform) and a JDK.
- Network access. The patcher downloads Alpine packages on each run and avbtool on the first run.
- A GSI `system.img` that you downloaded yourself, unpacked to raw ext4. A sparse image needs `simg2img`
  first. Keep it under `$HOME`, the only path colima shares with docker by default.
- An LP3 with an unlocked bootloader, to boot the result through DSU.

The pack was tested on MisterZtr's LineageOS 23.2 GSI. If you use another GSI build, first run
`scripts/check-sepolicy.sh`: a product policy that doesn't compile stops the GSI from booting
([`atel/README.md`](atel/README.md) explains why).

1. Build the pack. The payload goes to `out/payload/`.

   ```
   scripts/build-payload.sh
   ```

2. Patch your GSI image. The patcher copies `system.img` and never changes it. It refuses to overwrite an
   existing `lp3.img`, so delete that file before a re-run.

   ```
   BUILD_PROP_PATH=/system/product/etc/build.prop scripts/patch-gsi.sh system.img lp3.img out/payload
   ```

3. Compress the image and print the DSU install commands. The script runs no adb itself.

   ```
   scripts/pack-dsu.sh lp3.img lp3.img.gz
   ```

4. Run the printed `adb` commands, and confirm the install on the phone if it asks.
5. When the install finishes, boot the GSI. This enable lasts one boot, and the next reboot returns to
   LightOS.

   ```
   adb shell gsi_tool enable --single-boot
   adb reboot
   ```

6. In the GSI, install the Qualcomm IMS app from phh's Treble settings (IMS section).
7. Reboot to LightOS, then repeat step 5. VoLTE is available from this boot on.
8. In the GSI, turn on mobile data (it starts off for a SIM new to the GSI). On US Mobile, also set the APN:
   `scripts/apn/set-apn.sh darkstar` or `lightspeed` ([why](docs/apn.md)).

For options, label rules and AVB footer handling, see the [`patch-gsi.sh` reference](docs/patch-gsi.md).
To replace stock `system` instead of using DSU, see [full flash](docs/full-flash.md). Never wipe the LP3 with
`fastboot -w`: the phone then stops at "Can't load Android system".

## Contributing test results

Run the [test checklist](docs/checklist.md) and report your carrier's results in an issue. Never paste IMEI,
IMSI, ICCID, EID, phone numbers, serial numbers, MAC addresses or account emails into an issue or log. A
pre-push hook
(`.githooks/pre-push`, enable with `git config core.hooksPath .githooks`) rejects them in this repo.

## Credits

- [Vandam](https://github.com/vandamd) for the LP3 bootloader unlock, the installer and the
  [light-guide](https://github.com/vandamd/light-guide) GSI tweaks this builds on.
- [MisterZtr](https://github.com/MisterZtr) for the [LineageOS GSI](https://github.com/MisterZtr/LineageOS_gsi).
- [phh (Pierre-Hugues Husson)](https://github.com/phhusson) and [TrebleDroid](https://github.com/TrebleDroid)
  for the Treble GSI work and the IMS patches.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
