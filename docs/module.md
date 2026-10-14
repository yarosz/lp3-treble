# Module form (KernelSU / Magisk)

`scripts/build-module.sh` builds `out/lp3-treble-module-<version>.zip` from the image form's payload
(`build-payload.sh`), so both forms ship the same files. Install it from the Magisk app, or from the KernelSU app
with a mounting metamodule installed, then reboot. On KernelSU, including the ReSukiSU that vandamd/light-guide
installs, use our [meta-overlayfs build](../metamodule/README.md): install it first and reboot, then install the
lp3-treble module and reboot. A module installed before the metamodule must be installed again. Remove the lp3-treble module from the
same app to uninstall; nothing is left behind except the `camera_launch` setting (below).

Without a metamodule, KernelSU does not mount a module's `system/` directory: the overlays and keylayouts are
then missing, while `system.prop`, the incoming-SMS helper and `camera_launch` still apply. `service.sh` logs a warning (logcat tag
`lp3-atel`) when it sees the overlays are not mounted.

Status (2026-10-14, see the [checklist](checklist.md)): tested on the LP3 with KernelSU (ReSukiSU) on the plain
MisterZtr GSI, with and without our meta-overlayfs build. With it, all overlays are enabled and the keylayouts
are in use; without it, only the props, `camera_launch` and `lp3-atel-ready` apply. `lp3-atel-ready` runs and
sends its call to both SIM slots, and the module uninstalls cleanly. Not tested: VoLTE calls and incoming SMS
with the screen off on the module form, and Magisk. vandamd/light-guide's installer (as of its `flash.js` when
this was written) installs no metamodule: add ours from the ReSukiSU app.

| In the module | Image form equivalent |
|---|---|
| `system/product/overlay/*.apk` | same files |
| `system/usr/keylayout/*.kl` | same files |
| `system/product/framework/lp3-atel-ready.jar` | same file |
| `system.prop` | `props/product.prop`, appended to `/product/etc/build.prop` |
| `service.sh` | `atel/lp3-atel-ready.rc` + launcher + `lp3_atel` SELinux domain; README step 9 (`camera_launch`) |

Release builds set `MODULE_VERSION` and `MODULE_VERSION_CODE`. The defaults (`git describe`, commit count) are
for local builds; a shallow clone gives a low version code, which the root manager reads as a downgrade.

`service.sh` also turns on LineageOS's `camera_launch` setting (the shutter opens the camera) once, for user 0,
if it was never set. A value the user set is kept, and removing the module leaves the setting as it is.

## Why lp3-atel-ready runs differently

A module cannot add init `.rc` files: init has read them before the root manager mounts modules. So
`service.sh`, which the root manager runs late in boot, does the `.rc` file's job. Every 2 seconds it reads the
process ids of qcril (`qcrilNrd`, one process per SIM slot) and starts `lp3-atel-ready` whenever a new one
appears: once after boot, and again after any qcril restart, however quick. A new run replaces one still
retrying, as the `.rc`'s `restart` does. On a phone without a qcril binary it logs once and exits.
`scripts/test-module-service.sh` checks these cases on the host.

It loads the jar from the module directory, so the SMS fix does not depend on `system/` being mounted.

It runs as root in the root manager's SELinux domain, which can reach the telephony HAL, so the module ships no
SELinux policy. The image form runs it as the `radio` user in the narrow `lp3_atel` domain, because init starts
it there without a root manager. Only the `radio` identity has been tested end to end; from root, the call is sent
(the module test above), but the call is oneway, so that qcril accepts it is not yet verified.
