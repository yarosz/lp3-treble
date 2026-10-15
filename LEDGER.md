# Ledger

Public progress log for lp3-treble. No personal data: no identifiers, numbers, accounts or logs that
haven't been scrubbed.

## Now

- Phase: P5 (checklist and early previews). Tested on the LP3 with US Mobile on both AT&T and T-Mobile
  networks: calls, SMS, MMS, data, fingerprint, passkeys, keys, display; Wi-Fi Calling on the T-Mobile network
  (full flash);
  installed via DSU and via full flash, with a rollback to stock LightOS ([`docs/checklist.md`](docs/checklist.md)).
- Early previews (pre-releases): `v0.1.0-preview.1` and `v0.1.0-preview.2`, both 2026-10-14. Next: testers on
  Verizon, physical SIMs and carriers other than US Mobile.

## Open items

- Wi-Fi Calling: stock firmware sets the framework's WLAN data, WLAN network and qualified-networks services to
  Qualcomm's `vendor.qti.iwlan` (in /vendor) through a Qualcomm overlay in /product, which a GSI replaces;
  `overlays/wfc` restores that. It is on by default since 2026-10-14: once the tested line had Wi-Fi Calling turned
  on in the carrier account (it needs an E911 address), Wi-Fi calls in and out passed on stock LightOS and on the
  GSI (full flash). Still open: other carriers, AT&T's network, and the module form with `wfc`.
- Qualcomm's `.qtidataservices` (CNE) crashed once on the GSI with the Wi-Fi Calling overlay installed
  (`IllegalArgumentException: NetworkCallback was not registered` in `DataCallAgent.tearDownDataCall`). Not checked
  for in the 2026-10-14 full-flash run; worth a logcat check in the next test with the overlay.
- The module form (`docs/module.md`) was tested 2026-10-14 with KernelSU (ReSukiSU), with and without our
  meta-overlayfs build (`metamodule/`): with it, overlays and keylayouts are active. Still open on the module
  form: VoLTE calls, Magisk, and incoming SMS with the screen off (qcril accepting the call from root).
- On T-Mobile's default APN (`fast.t-mobile.com`, IPV6 or IPV4V6), IPv6 and NAT64 work (`64:ff9b::/96`
  reachable, DNS64 answers), but the modem also puts an IPv4 address from 192.0.0.0/27 on the data interface
  with a default route. Android sees IPv4, so its CLAT (clatd) never starts, and IPv4 through that address gets
  no replies (a TCP connect succeeds, then an HTTP request times out; ping fails). Stock LightOS behaves the same
  way on that APN (tested); it avoids the problem by shipping an IPv4 APN, and so does
  `scripts/apn/set-apn.sh lightspeed` (verified: native IPv4, HTTP works). Open: whether the pack should set
  the IPv4 APN itself.
- The IMS static overlays were confirmed on single fresh-install runs on one AT&T-network SIM; confirm over more
  fresh installs and on other carriers.
- `scripts/container/patch.sh` refuses to append a `ro.*` key already in the target `build.prop`, citing "init
  keeps the first value". Init most likely lets a later value win (product props do override vendor ones here);
  verify on a device and relax or reword the check.
- More AT&T network codes (Cricket 310/150, FirstNet 313/100) for the CarrierConfig overlay need testers
  with those SIMs.
- `test-patch-gsi.sh` has no seed with an FEC footer (avbtool needs an external `fec` binary that Alpine doesn't
  ship). The real GSI's FEC footer is covered only by the on-device run.

## Findings

- Test device runs firmware `00WW_1_440000`: Android 14 system on an Android 12 vendor (VNDK 32), virtual
  A/B, dynamic partitions.
- DSU is present on stock LightOS: `gsi_tool`, the `gsid` service and the DSU installer app. An unsigned GSI
  can boot in DSU only after a bootloader unlock. DSU boots the stock kernel.
- Qualcomm IMS (`org.codeaurora.ims` and friends) lives in `/system_ext`, which a GSI replaces. VoLTE on the GSI
  uses phh's Qualcomm IMS app, which the user installs (tested by `adb install`). This repo never ships it.
- The MisterZtr LineageOS 23.2 GSI already declares `android.software.credentials`.
- LightOS Tools are clients of LightOS's own `com.lightos` service (a Tool's `lighttool.toml` names it as
  `serverPackage`), which runs as a system app signed with Light's key and is part of the system a GSI replaces.
  So Tools don't run on the GSI.
- Its EXT4 image is raw ext4 with almost no free space or inodes, so patching grows it with `resize2fs` first.
- The image ends in an AVB hashtree footer with FEC (2 roots). DSU sets up dm-verity with FEC from it, so
  edited blocks were silently corrected back to stock at boot. `patch-gsi.sh` now replaces the footer (no FEC,
  unsigned); an image built this way booted in DSU on the LP3 with every patched file live and no FEC
  corrections in the kernel log.
- On the GSI, incoming SMS were lost whenever the screen was off: the Qualcomm RIL holds them until it is told
  the telephony UI is ready, a signal stock firmware sends from a `/system_ext` app. `lp3-atel-ready` sends it
  (`atel/README.md`). Incoming VoLTE calls still work with it (answered, call log VoLTE). The same fix was merged
  upstream in TrebleDroid (device_phh_treble#88): GSIs built from device_phh_treble after that merge should include
  it. `lp3-atel-ready` is still needed on the MisterZtr 23.2 build tested here.

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
| P5 | Test checklist, known issues, early previews |

## Log

- 2026-10-11: Repo created. P0 read-only checks and research done.
- 2026-10-11: Offline image patcher (`patch-gsi.sh`, `pack-dsu.sh`) and self-test added; self-test passes on a synthetic image. Not yet run on the real GSI.
- 2026-10-12: CarrierConfig overlay (VoLTE on AT&T SIMs): calls both ways and outgoing SMS work in the GSI.
- 2026-10-12: `patch-gsi.sh` replaces the GSI's AVB hashtree footer, so patched files survive DSU (#4).
- 2026-10-12: `lp3-atel-ready` (init service, own SELinux domain): incoming SMS arrive with the screen off and in
  deep doze, on an enforcing image with this repo's files. Outgoing SMS and calls unchanged; incoming VoLTE calls
  pass with it (see Findings).
- 2026-10-12: `ims-caf` and `ims-caf-framework` static overlays: VoLTE comes up on the first boot after installing
  the IMS app (#5).
- 2026-10-12: Checklist on US Mobile's AT&T network (DSU): calls, SMS and MMS pass; data passes after setting the
  carrier APN.
- 2026-10-13: Checklist on US Mobile's T-Mobile network (DSU): calls, SMS, MMS and data pass. Passkeys pass (DSU).
- 2026-10-13: Module form (KernelSU / Magisk) and keylayouts in the public pack; US Mobile APN script, T-Mobile
  IPv4 gap documented.
- 2026-10-14: Test checklist and full-flash procedure; full flash and rollback to stock LightOS tested.
  `v0.1.0-preview.1` released.
- 2026-10-14: Hardware sweep (cameras, GPS, NFC, Bluetooth and more) passes; auto-brightness overlay;
  experimental Wi-Fi Calling overlay.
- 2026-10-14: Shutter as a camera button; Settings > Buttons crash fixed; carrier name for SIMs identified as
  T-Mobile US; meta-overlayfs metamodule build, module tested on KernelSU with it.
- 2026-10-14: Wi-Fi Calling works once the line has it: calls in and out on stock LightOS and on the GSI (full
  flash); `overlays/wfc` on by default. `v0.1.0-preview.2` released.
