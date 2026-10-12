# lp3-atel-ready: incoming SMS with the screen off

## The problem

On a GSI, the LP3 sends texts but loses incoming ones whenever the screen is off or the phone dozes. The
sender's carrier retries for a while, then gives up. With the screen on, the same texts arrive.

The Qualcomm RIL (qcril, in the stock vendor partition) has a power-saving mode. Until it has been told that
the Android telephony UI is ready, it parks each incoming SMS in a buffer while the screen is off, waits for
the UI, and drops the SMS after about 20 seconds without acknowledging it. On stock LightOS a Qualcomm
system app sends that "UI ready" signal once per boot and per SIM slot. That app lives in `/system_ext`,
which a GSI replaces, so on a GSI nobody sends it.

## The fix

`lp3-atel-ready` sends the same signal. It is a small Java program run with `app_process`:

| File (in the image) | Source | What it is |
|---|---|---|
| `/product/bin/lp3-atel-ready` | `lp3-atel-ready.sh` | Launcher; init starts it in the `lp3_atel` SELinux domain |
| `/product/framework/lp3-atel-ready.jar` | `src/lp3treble/AtelReady.java` | Sends the signal to each SIM slot's hook |
| `/product/etc/init/lp3-atel-ready.rc` | `lp3-atel-ready.rc` | Starts it after boot and after a qcril restart |
| `/product/etc/selinux/product_sepolicy.cil` | `lp3_atel.cil` | The `lp3_atel` domain |
| `/product/etc/selinux/product_file_contexts` | `product_file_contexts` | Labels the launcher |

`scripts/build-atel.sh` builds the jar and stages these files under `out/atel/payload/` for `patch-gsi.sh`.
The MisterZtr GSI ships both `product_*` SELinux files empty, so the pack replaces them whole.

Behaviour:

- init starts it when `sys.boot_completed=1` and a qcril service (`vendor.qcrild`, `vendor.qcrild2`) is
  running, so it runs once after boot and again each time qcril restarts. On a vendor without those
  services it never starts.
- It sends to `oemhook0` and `oemhook1` (one per slot). A hook that is not registered yet is retried with
  backoff for about two minutes, then it logs which slots it reached (logcat tag `lp3-atel`) and exits 0.
  It is `oneshot`: init never respawns it.
- The `lp3_atel` domain: only init can enter it. It is a telephony HAL client
  (`hal_telephony_client`, which the vendor policy lets call the qcril hook), plus what `app_process` needs
  to start ART. It registers no binder service.
- It runs as the `radio` user with no capabilities.

## How it was found

By observation on the LP3, with qcril's own logcat turned on. An incoming SMS reached qcril
(`QMI_WMS_EVENT_REPORT_IND`), was held in a "power opt" buffer, and expired after 20 seconds. qcril logs an
"ATEL UI READY" status per slot, and with the screen off the buffer was only skipped when that status was 1.
On stock LightOS, logcat shows qcril receiving OEM hook request id 524314 with a one-byte payload of 1 once per
slot after boot, which sets that status to 1. Sending the same request (interface name, instance names, request
id and payload as observed) from our own code makes screen-off and dozing SMS arrive on the GSI.

This repo contains no Qualcomm or Light code, interface definitions, generated stubs or decompiled sources.
The request is built byte by byte from the observed values and sent as a raw HIDL parcel.

## Tested

LP3 (TLP301), stock vendor `00WW_1_440000`, MisterZtr LineageOS 23.2 GSI via DSU, SELinux enforcing, AT&T
network: incoming SMS with the screen off and in forced deep doze; outgoing SMS and VoLTE calls unchanged.
