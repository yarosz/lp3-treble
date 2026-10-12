# Ledger

Public progress log for lp3-treble. No personal data: no identifiers, numbers, accounts or logs that
haven't been scrubbed.

## Now

- Phase: P0 done (setup and read-only research). Nothing installable yet.
- Next: capture stock LightOS resources and props; build the offline image-patching script; first overlays.

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
