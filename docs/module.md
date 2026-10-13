# Module form (KernelSU / Magisk)

`scripts/build-module.sh` builds `out/lp3-treble-module-<version>.zip` from the same sources as the image form.
Install it from the KernelSU or Magisk app on a rooted GSI, then reboot. Remove it from the same app to
uninstall; nothing is left behind.

Status: built from the same files the image form was tested with on the LP3, but **not yet tested as a module**
(it needs a GSI with KernelSU or Magisk).

| In the module | From | Image form equivalent |
|---|---|---|
| `system/product/overlay/*.apk` | `overlays/` | same files |
| `system/usr/keylayout/*.kl` | `keylayout/` | same files |
| `system.prop` | `props/product.prop` | appended to `/product/etc/build.prop` |
| `system/product/framework/lp3-atel-ready.jar` | `atel/src/` | same file |
| `service.sh` | `module/service.sh` | `atel/lp3-atel-ready.rc` + launcher + `lp3_atel` SELinux domain |

## Why lp3-atel-ready runs differently

A module cannot add init `.rc` files: init has read them before the root manager mounts modules. So
`service.sh`, which the root manager runs late in boot, does the `.rc` file's job: it runs `lp3-atel-ready`
once after boot and again each time a qcril service (`vendor.qcrild`, `vendor.qcrild2`) goes back to
`running`. It checks every 10 seconds. On a phone without those services it logs once and exits.

It runs as root in the root manager's SELinux domain, which can already reach the telephony HAL, so the
module ships no SELinux policy. The image form needs the narrow `lp3_atel` domain because init starts it
there without a root manager.
