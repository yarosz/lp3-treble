# Device tools

Scripts that drive an LP3 from a computer over adb and fastboot: install and boot the GSI through DSU, take
one-boot root, back up, full flash and roll back. They were written while developing lp3-treble with AI assistance
(Claude Code), and are plain bash and Python scripts that people and agents can both run.

## Prerequisites

- A recent Android platform-tools (`adb`, `fastboot` with fastbootd support) and an LP3 with the bootloader
  unlocked and adb turned on (Developer Mode: dial `*7412369#` in the Phone tool).
- macOS. A few scripts use BSD `stat -f` and `sed -i ''`, and the backup bundle scripts need `hdiutil` and
  `osascript`. `zstd` for the partition dump, `python3` for `ui-dump.sh`.
- The serial: scripts take it as an argument, or read `ANDROID_SERIAL` (the variable adb itself reads) where the
  argument is optional. `adb devices` prints it.
- Scripts named "device side" are fed to the phone's shell: `adb shell < tools/<script>`.
- Read the [device safety rules](../AGENTS.md#device-safety) first. The scripts keep them: no `fastboot -w`, no
  `adb root` on the GSI, slot `a` only, full flash only with a verified dump.

## Scripts

| Script | What it does | Needs |
|---|---|---|
| `dsu-install.sh` | Wipes the old DSU image, pushes a patched `.img.gz` and starts the DSU install | LightOS booted; serial, image, raw size |
| `wait-dsu-ready.sh` | Waits until `gsi_tool status` says installed | |
| `dsu-oneshot.sh` | Device side: arms the DSU image for one boot | |
| `gsi-reboot.sh` | Boots the installed DSU GSI again (via LightOS if needed) and waits for boot | |
| `to-lightos.sh` | Leaves the DSU GSI for stock LightOS | |
| `wait-boot-completed.sh` | Waits for `sys.boot_completed` | |
| `gsi-fresh-boot.sh` | First boots after a DSU install: LTE, IMS app, provisioned flag, second boot, waits for service and IMS | phh's IMS APK |
| `gsi-ims-setup.sh` | Allows LTE/NR on SIM slot 1 and installs phh's IMS APK | phh's IMS APK, downloaded from phh (treble.phh.me) |
| `gsi-set-lte.sh` | Device side: allowed network types NR/LTE/WCDMA/GSM on SIM slot 1 | |
| `wait-in-service.sh` | Waits for voice IN_SERVICE | `ANDROID_SERIAL` |
| `wait-ims-reg.sh` | Waits for IMS registration in the GSI's logs | |
| `ui-dump.sh` | Prints each on-screen node with text and its centre | `python3` |
| `gsi-ui.sh` | Lists ids and texts, taps a node by regex, shows the focused window (numbers masked) | `ANDROID_SERIAL` |
| `temp-root-boot.sh` | One-boot root on stock LightOS with `fastboot boot` (writes nothing) | light-guide's `resukisu-boot.img`, firmware `00WW_1_440000` |
| `partition-dump.sh` | Streams partitions to the computer, compressed, verified against device sha256 and size | temp root, `zstd` |
| `verify-dump.sh` | Re-verifies a partition dump against its manifest | `zstd` |
| `fullflash.sh` | `dryrun` / `flash` of a patched image onto slot `a` ([full flash](../docs/full-flash.md)) | verified dump, `rollback.sh prep` |
| `rollback.sh` | `prep` / `check` / `flash`: restores `super`, `vbmeta_a` and `boot_a` from the dump | verified dump with those three |
| `user-data-backup.sh` | Pulls media, SMS, MMS, call log and contacts before a wipe | |
| `backup-encrypt.sh` | macOS only: copies backups into an AES-256 sparse bundle and verifies them; passphrase from a hidden dialog | `hdiutil` |
| `backup-attach.sh` | macOS only: mounts that bundle at `/Volumes/LP3-backup` | `hdiutil` |

Backups and dumps hold personal data and Light's software: keep them private.
