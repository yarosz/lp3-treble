# AGENTS.md

Instructions for coding agents (and people) working in this repo. Read `README.md` first for what the pack is.

## Layout

| Path | Contents |
|---|---|
| `overlays/<name>/` | One runtime resource overlay (RRO) each: `AndroidManifest.xml` + `res/`. Built by `scripts/build-overlays.sh` |
| `overlays-experimental/` | Overlays built only with `LP3_EXPERIMENTAL=1` (for example `wfc`, Wi-Fi Calling) |
| `keylayout/` | Key layout files for the LP3's input devices |
| `props/product.prop` | Props appended to the GSI's product `build.prop` |
| `atel/` | `lp3-atel-ready` (Java, raw HIDL parcel), its init `.rc` and SELinux `.cil` ([README](atel/README.md)) |
| `module/` | KernelSU / Magisk module scripts (`service.sh`) |
| `scripts/` | Build, patch, pack and check scripts; `scripts/apn/` runs against a phone over adb |
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
  delete logical partitions), and only with a dump of `super` and `vbmeta_a` whose sizes and sha256 you verified.
  The flash and the rollback both wipe userdata. There is no public LP3 factory image.
- Don't take a Light OTA on an unlocked or flashed phone: the dump would no longer match the firmware, and the
  rollback restores the partitions as they were at backup time.
