# About the IMS overlays

VoLTE calls on the GSI need the Qualcomm IMS app (`org.codeaurora.ims`). Stock LightOS keeps it in
`/system_ext`, which a GSI replaces, so you install phh's build of it from the Treble app. This repo never
ships it.

## Why the pack sets the IMS config itself

phh's GSI already has overlays that point telephony at the Qualcomm IMS app, but they switch on late:

- `me.phh.treble.overlay.cafims` (target `android`) sets `config_device_volte_available`. It is static but
  gated on `persist.sys.phh.ims.caf=true`, a prop the Treble app writes about 30 s after each boot.
- `me.phh.treble.overlay.cafims_telephony` (target `com.android.phone`) sets `config_ims_mmtel_package`.
  It is mutable, and the Treble app enables it after boot.

Telephony reads both values early in boot. On a fresh install, VoLTE therefore came up only on the second
boot after installing the IMS app: one boot with VoLTE marked unavailable or the IMS app unbound, then a
working one. Once those overlays were on, 6 boots in a row all had VoLTE.

`overlays/ims-caf` (`config_ims_mmtel_package=org.codeaurora.ims`) and `overlays/ims-caf-framework`
(`config_device_volte_available=true`) set the same values as static overlays, so they apply from the first
boot. With them, the first boot after installing the IMS app had VoLTE. That result comes from single
fresh-install runs on one LP3 with an AT&T-network SIM (see `LEDGER.md`). The values match phh's overlays as of
phhusson/treble_app's `QtiAudio.kt` (`handleDynIms`) and `Ims.kt`, October 2026. Keep them in sync if phh
changes those.

## Trade-off

The device VoLTE flag is global. With any SIM, the carrier config still decides whether VoLTE is offered.
A phone without the IMS app also reports VoLTE as available, so a Settings toggle can appear that does
nothing. Without the IMS app, two test boots showed no telephony crashes and no IMS service bound. Calls
were not tested in that state. To opt out, leave both overlays out of your payload.
