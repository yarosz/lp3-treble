# Ledger

Public progress log for lp3-treble. No personal data: no identifiers, numbers, accounts or logs that
haven't been scrubbed.

## Now

- Phase: P4 (IMS and carrier configuration), AT&T network first. Nothing to install yet: no release.
- Done in P3-P4, tested on the LP3 in DSU: keylayouts, density 320, LTE default network mode, CarrierConfig
  overlay (VoLTE for AT&T SIMs), and `lp3-atel-ready` (incoming SMS with the screen off, `atel/README.md`).
- Next: the full checklist per network.

## Open items

- More AT&T network codes (Cricket 310/150, FirstNet 313/100) for the CarrierConfig overlay need testers
  with those SIMs.
- Incoming call after `lp3-atel-ready`: expected unaffected (it only changes SMS buffering); live test pending.
- `test-patch-gsi.sh` has no seed with an FEC footer (avbtool needs an external `fec` binary that Alpine doesn't
  ship). The real GSI's FEC footer is covered only by the on-device run.

## Findings

- Test device runs firmware `00WW_1_440000`: Android 14 system on an Android 12 vendor (VNDK 32), virtual
  A/B, dynamic partitions.
- DSU is present on stock LightOS: `gsi_tool`, the `gsid` service and the DSU installer app. An unsigned GSI
  can boot in DSU only after a bootloader unlock. DSU boots the stock kernel.
- Qualcomm IMS (`org.codeaurora.ims` and friends) lives in `/system_ext`, which a GSI replaces. Calls over
  VoLTE will need phh's Qualcomm IMS path or a script that copies the APK from your own phone. This repo
  never ships it.
- The MisterZtr LineageOS 23.2 GSI already declares `android.software.credentials`.
- Its EXT4 image is raw ext4 with almost no free space or inodes, so patching grows it with `resize2fs` first.
- The image ends in an AVB hashtree footer with FEC (2 roots). DSU sets up dm-verity with FEC from it, so
  edited blocks were silently corrected back to stock at boot. `patch-gsi.sh` now replaces the footer (no FEC,
  unsigned); an image built this way booted in DSU on the LP3 with every patched file live and no FEC
  corrections in the kernel log.
- On the GSI, incoming SMS were lost whenever the screen was off: the Qualcomm RIL holds them until it is told
  the telephony UI is ready, a signal stock firmware sends from a `/system_ext` app. `lp3-atel-ready` sends it
  (`atel/README.md`).

- IMS voice came up off on the first boots after a fresh install (calls fell back to circuit-switched and AT&T
  rejected them), once with the Qualcomm IMS app not bound at all. Cause: phh's overlays for the device VoLTE flag
  and the IMS service package switch on only after a boot, through the Treble app (one is gated on a prop it writes
  30 s after boot, the other is enabled at runtime). Across 6 boots in a row of a settled install, voice was on
  every time. The `ims-caf` and `ims-caf-framework` overlays set both statically: after a fresh install
  without the IMS app, two boots showed no telephony crashes, and the first boot after installing the IMS app had
  voice on.

## Plan

| Phase | Work |
|---|---|
| P0 | Repo, read-only device checks, research |
| P1 | Baseline calls, SMS, MMS and data on stock LightOS; capture stock resources and props |
| P2 | Bootloader unlock; first DSU boot of a patched GSI image |
| P3 | Overlays and props: keys, display, fingerprint, credentials feature |
| P4 | IMS and carrier configuration |
| P5 | Test checklist, known issues, early preview |

## Log

- 2026-10-11: Repo created. P0 read-only checks and research done.
- 2026-10-11: Offline image patcher (`patch-gsi.sh`, `pack-dsu.sh`) and self-test added; self-test passes on a synthetic image. Not yet run on the real GSI.
- 2026-10-12: CarrierConfig overlay (VoLTE on AT&T SIMs): calls both ways and outgoing SMS work in the GSI.
- 2026-10-12: `lp3-atel-ready` (init service, own SELinux domain): incoming SMS arrive with the screen off and in
  deep doze, on an enforcing image with this repo's files (patched by a private patcher build that regenerates
  the AVB footer; see Open items). Outgoing SMS and calls unchanged; incoming call test pending.
