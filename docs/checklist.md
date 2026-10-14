# Test checklist

Results for the first preview, and the checklist to run on your own carrier. Device: Light Phone III (TLP301),
firmware `00WW_1_440000`, bootloader unlocked. GSI: MisterZtr's LineageOS 23.2 (VANILLA, EXT4) with the full
pack patched in by `scripts/patch-gsi.sh`. IMS: phh's Qualcomm IMS app, installed by the user (the pack does not
ship it).

## How to test

1. Build and boot a patched image through DSU (README, "Build a test image"), or flash it
   ([full flash](full-flash.md)).
2. In the GSI, install the IMS app from phh's Treble settings (IMS section) and reboot once (in DSU: reboot to
   LightOS, then boot the GSI again).
3. Turn on mobile data. If your carrier needs a specific APN, set it ([APNs](apn.md)).
4. Work through each row of the table below. Use a second phone for incoming calls and texts: some networks
   don't loop back texts sent to your own number.
5. Report the results in an issue: carrier and network (for example "US Mobile on T-Mobile"), install method
   (DSU or full flash), and PASS / FAIL / N/A per row (N/A for a row you skipped), with what you saw on a FAIL.
   If the IMS app won't install or IMS never registers, report that and stop there: the call and SMS rows
   depend on it. Never paste IMEI, IMSI, ICCID, EID,
   phone numbers, serial numbers or account emails.

| Item | How |
|---|---|
| IMS (VoLTE) registered | Dial `*#*#4636#*#*` > Phone information: IMS registration "Registered" and Voice over LTE "Available". Or `adb logcat -d \| grep "MmTel Capabilities"` shows `Voice: true`. The VoLTE switch in Settings is not proof (see known issues) |
| Call out, call in | Place and answer a call; audio both ways |
| SMS out, SMS in | Also with the screen off for a few minutes before the text arrives |
| MMS out, MMS in | A picture message, or a group text with two other people |
| Mobile data | Wi-Fi off, open a web page |
| Fingerprint | Enroll in Settings > Security, unlock from the lock screen |
| Passkeys | Optional: a credential provider app plus a passkey test site |
| Keys | Scroll wheel (brightness), shutter, HOME |
| Display | Text and icons at the stock size (density 320) |

## Results

### US Mobile on AT&T ("Dark Star", 310/280, eSIM), DSU, 2026-10-12

| Item | Result | Evidence |
|---|---|---|
| Pack files live, density 320, keylayouts, overlays, `lp3-atel-ready`, IMS app, MmTel voice | PASS | `gsi-pack-check`, 21 checks |
| VoLTE call out | PASS | call log features=64 |
| VoLTE call in | PASS | features=64 |
| SMS out | PASS | |
| SMS in, screen on / screen off / forced deep doze | PASS | received in each state |
| MMS out (image + text) | PASS | MMS server response 128 (OK) |
| MMS in (image + text) | PASS | downloaded 12 s after sending |
| Mobile data | PASS after setting the carrier APN | cellular validated |

### US Mobile on T-Mobile ("Light Speed", 310/240, eSIM), DSU, 2026-10-13

The same line, moved by a network transfer.

| Item | Result | Evidence |
|---|---|---|
| Pack check | PASS | |
| VoLTE on the first GSI boot with the new SIM | PASS | MmTel voice and SMS available |
| VoLTE call out | PASS | features=68 (VoLTE + HD audio) |
| VoLTE call in | PASS | features=64 |
| SMS out | PASS | delivered to another number |
| SMS in, screen off / forced deep doze | PASS | |
| MMS out (image + text) | PASS | MMS server response 128 (OK) |
| MMS in (image + text) | PASS | downloaded 12 s after sending |
| Mobile data | PASS after turning mobile data on | see the APN known issue |

### US Mobile on T-Mobile, full flash, 2026-10-14

The same image flashed to `system_a`, then rolled back to stock LightOS ([full flash](full-flash.md)). Only the
T-Mobile network was tested on the full flash. The AT&T-network results above come from DSU; they should carry
over, because both installs run the same image on the same vendor, modem and kernel.

| Item | Result | Evidence |
|---|---|---|
| Boot | PASS after a factory reset in recovery | the first boot stopped at "Can't load Android system" because userdata was wiped with `fastboot -w` (see known issues) |
| Pack check | PASS | |
| VoLTE registration | PASS | |
| Mobile data | PASS with the IPv4 APN | |
| VoLTE call out | PASS | features=68, audio both ways |
| VoLTE call in | PASS | features=64 |
| SMS out / SMS in | PASS / PASS | |
| Group MMS with two other people | PASS | received; reply sent and delivered |
| Keys | PASS | |
| Rollback to stock LightOS | PASS | |

### Fingerprint, DSU, 2026-10-14

| Item | Result | Evidence |
|---|---|---|
| Enroll (side-key sensor, test PIN as backup lock) | PASS | `dumpsys fingerprint` count 1 |
| Lock-screen unlock | PASS | touch only, from the dozing screen |
| BiometricPrompt in an app | PASS | KeePassDX user verification for a passkey; 4 accepted, 0 rejected |

### Passkeys, DSU, 2026-10-13

KeePassDX 4.5.5 (libre build) as the credential provider, Cromite 153 as the browser, webauthn.io as the site.

| Item | Result |
|---|---|
| `android.software.credentials` | PASS |
| Provider listed in Settings > Passwords, passkeys & accounts | PASS |
| Passkey created, then used to sign in | PASS |

Setup notes: in Cromite, turn on Settings > Password Manager > "Enable Android Credential Manager" (off by
default; without it the site gets NotAllowedError). In KeePassDX, turn on Settings > Device unlocking > "Device
credential unlocking", or it refuses user verification. KeePassDX asks once to trust Cromite as a privileged app.

### Keys and display, DSU, 2026-10-14

Same mapping as vandamd/light-guide (`keylayout/`). Scroll wheel (scancodes 19/20) → brightness up/down; wheel
press (66) → F8; shutter half press (80) → NUMPAD_2, full press (27) → RIGHT_BRACKET; HOME (102) → home screen.
Volume up (gpio-keys 115) and volume down (`pmic_resin`, Android's generic layout) change the volume. Display
density 320. All PASS.

### Hardware, DSU, US Mobile on T-Mobile, 2026-10-14

| Item | Result | Evidence |
|---|---|---|
| Back camera, photo with flash | PASS | LineageOS Aperture; 12 MP photo, flash fired |
| Front camera | PASS | preview and photo |
| Flashlight | PASS | quick settings tile |
| Vibration | PASS | felt; also on volume changes |
| Proximity sensor in a call | PASS | screen off at the ear, back on away from it |
| GPS | PASS | fix in about 20 s indoors, 13 satellites (GPS + Galileo, including L5), accuracy about 4 m |
| NFC | PASS | read an NTAG213 emulated by a Flipper Zero; Android opened the tag's URL |
| Bluetooth | PASS | found nearby devices; paired with a Flipper Zero (LE) and AirPods (classic) |
| Auto-brightness | PASS with `overlays/framework` | stock LightOS's curve; covering the sensor (12 lux) dimmed the screen to 8 %, uncovering it (about 300 lux) brought it back to 100 % |
| Wi-Fi Calling | FAIL | with `overlays/framework` the switch appears and can be turned on, but calls don't go over Wi-Fi: in "Wi-Fi only" mode an outgoing call never connected, and the phone never tried to reach the carrier's Wi-Fi Calling server |
| Bluetooth audio | PASS | AirPods: music (A2DP) and a call with audio both ways (headset microphone) |

## Known issues

- **Don't wipe with `fastboot -w` on the LP3.** fastboot formats userdata with the type the bootloader reports
  (ext4), but the phone mounts userdata as f2fs, so the next boot stops at "Can't load Android system". Use
  `fastboot erase userdata` and `fastboot erase metadata` instead (Android formats them on boot), or choose
  "Factory data reset" on that recovery screen.
- Calls and texts over LTE need phh's IMS app, installed by the user, and one reboot after installing it.
- Without the IMS app the device still reports VoLTE available, so the VoLTE toggle does nothing.
- The fingerprint enroll screen says the sensor is on the back of the device: the GSI doesn't know the LP3's
  side-key sensor location. Enrolling and unlocking work.
- The KernelSU / Magisk module is experimental and untested on a phone ([module](module.md)).
- US Mobile on AT&T needs its `ereseller` APN; the GSI's default AT&T APN never validates.
  `scripts/apn/set-apn.sh darkstar` ([APNs](apn.md)).
- US Mobile on T-Mobile: on the GSI's default `fast.t-mobile.com` APN, IPv4 gets no replies (IPv6 works). Stock
  LightOS behaves the same on that APN and ships an IPv4 APN instead. `scripts/apn/set-apn.sh lightspeed`.
- A SIM that is new to the GSI starts with mobile data off.
- Wi-Fi Calling doesn't work yet (tested on US Mobile's T-Mobile network). The pack turns the Settings switch on,
  but calls still don't go over Wi-Fi. It may also depend on the carrier.
- The shutter button doesn't take photos in the camera app: it keeps vandamd/light-guide's mapping.
- Not tested yet: uninstalling the pack from a full flash other than by restoring stock partitions; carriers
  other than US Mobile.
