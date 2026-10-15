# AGENTS.md

Instructions for coding agents (and people) working in this repo. Read `README.md` first for what the pack is.

## Layout

| Path | Contents |
|---|---|
| `overlays/<name>/` | One runtime resource overlay (RRO) each: `AndroidManifest.xml` + `res/`. Built by `scripts/build-overlays.sh` |
| `keylayout/` | Key layout files for the LP3's input devices |
| `props/product.prop` | Props appended to the GSI's product `build.prop` |
| `atel/` | `lp3-atel-ready` (Java, raw HIDL parcel), its init `.rc` and SELinux `.cil` ([README](atel/README.md)) |
| `module/` | KernelSU / Magisk module scripts (`service.sh`) |
| `metamodule/` | Patch and build for KernelSU's meta-overlayfs metamodule; **GPL-3.0**, unlike the rest ([README](metamodule/README.md)) |
| `scripts/` | Build, patch, pack and check scripts; `scripts/apn/` runs against a phone over adb |
| `scripts/test/` | Checklist test harness: scripts that reproduce `docs/checklist.md` rows on a phone in the GSI ([README](scripts/test/README.md)) |
| `tools/` | Device tools: DSU install and boot, one-boot root, partition dump, full flash and rollback, backups ([README](tools/README.md)) |
| `docs/` | Checklist, full flash, module, APN, IMS overlay and patcher docs |
| `.githooks/` | The pre-push privacy hook |
| `LEDGER.md` | Public progress record: add a line when a device result, release or decision lands |
| `out/` | Build output (ignored by git) |

## Build and test

- Pack: `scripts/build-payload.sh` (needs the Android SDK build-tools, android-36 platform and a JDK).
- Image: `scripts/patch-gsi.sh` (needs docker) and `scripts/pack-dsu.sh`. See `README.md`.
- Module: `scripts/build-module.sh`.
- Host tests, run before every PR: `scripts/test-module-service.sh`, `scripts/test-patch-gsi.sh`, and
  `scripts/check-sepolicy.sh` when the `atel/` policy or the target GSI changes (it needs the vendor policy
  files from an LP3; see its header).
- Device results go in `docs/checklist.md` with the date, the install form (DSU or full flash) and the carrier.
  Write down what was not tested.

## Device tools and test harness

- `tools/` drives the phone: start with DSU (`dsu-install.sh`, `wait-dsu-ready.sh`, `gsi-fresh-boot.sh`, then
  `gsi-reboot.sh` / `to-lightos.sh` to switch). The full-flash tools (`temp-root-boot.sh`, `partition-dump.sh`,
  `rollback.sh prep`, `fullflash.sh dryrun` before `flash`) come only after DSU testing and follow
  `docs/full-flash.md`.
- `scripts/test/` maps to the rows of `docs/checklist.md` (its README has the table). Phone numbers come from the
  `LP3_NUMBER` and `PEER_NUMBER` environment variables, the serial from `ANDROID_SERIAL` or an argument: never
  write them into a script.
- When you repeat a device sequence by hand, script it into one of these folders: minimal, only the steps you ran
  for real, no speculative options. Keep the header (what, usage, env, read-only or writes) and the safety rules
  below.

## Privacy (public repo)

- Never commit IMEI, IMSI, ICCID, EID, phone numbers, serial numbers (`ro.serialno`), MAC addresses, account
  emails, home addresses, Wi-Fi names or LAN addresses, in files or in commit messages. Scrub logs before
  committing them.
- Enable the hook once per clone: `git config core.hooksPath .githooks`. It runs `scripts/privacy-scan.sh` on
  every pushed commit and its message. Never bypass it with `--no-verify`. It catches long digit runs, phone
  numbers, emails and MACs only: check for serials, Wi-Fi names, street addresses and LAN IPs yourself.
- No vendor blobs and no Light or Qualcomm proprietary files (APKs, `.so`, `.hal`, partition images). Only
  overlays, props and code written here. When a fix needs a vendor file, ship a script that copies it from the
  user's own phone.

## Device safety

- **Never `fastboot -w`** on an LP3: the phone then stops at "Can't load Android system".
- **Never `adb root`** on the GSI: it kills adbd over USB and Wi-Fi until someone restarts the phone by hand.
- **DSU first.** Test every change in a DSU boot (`gsi_tool enable --single-boot`) before anyone flashes it.
- **Full flash only as written in `docs/full-flash.md`**: slot `a` only (stop if `current-slot` is `b`, never
  write a `_b` partition), stop if `snapshot-update-status` isn't `none` or the image doesn't fit `super` (never
  delete logical partitions), and only with a dump of `super`, `vbmeta_a` and `boot_a` whose sizes and sha256
  you verified. The flash and the rollback both wipe userdata. There is no public LP3 factory image.
- Don't take a Light OTA on an unlocked or flashed phone: the dump would no longer match the firmware, and the
  rollback restores the partitions as they were at backup time. Every userdata wipe (unlock, rollback, factory
  reset) turns LightOS updates back on, and LightOS setup may offer an update: never accept it when driving setup.
  Skip Wi-Fi in setup, turn updates off (`pm disable-user com.lightos.fota`), then connect Wi-Fi.
- **Never relock the bootloader.** vandamd/light-guide implements a relock: its "Restore LightOS" flow writes back
  stock `boot` and `vbmeta` (and `system` when coming from LineageOS), checks every pinned partition against stock
  hashes, erases `avb_custom_key`, then runs `flashing lock` and checks for green verified boot. But if a verified
  partition doesn't match stock when you relock, expect the phone to refuse to boot (standard Android Verified
  Boot behaviour), and no public EDL (Qualcomm emergency download) loader is known for the LP3 to recover it.
  Relocking has not been tested on this project's phone, and Vandam's page says the flow "still needs end-to-end
  testing". He keeps his own phone unlocked: "a future firmware update could prevent unlocking it again if
  relocked", so don't relock to take a Light update either. To go back to stock, use the rollback in
  [`docs/full-flash.md`](docs/full-flash.md), which leaves the bootloader unlocked.
