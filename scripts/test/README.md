# Checklist test harness

Scripts that reproduce the rows of the [test checklist](../../docs/checklist.md) on a phone booted in the patched
GSI. They were written while developing lp3-treble with AI assistance (Claude Code), and are plain bash and
JavaScript that people and agents can both run. The host tests (`scripts/test-module-service.sh`,
`scripts/test-patch-gsi.sh`) stay in `scripts/`.

## Prerequisites

- `adb`, and the LP3 booted in the GSI with adb on (`tools/gsi-reboot.sh`). macOS was used; `bash`, `python3`.
- Environment variables, digits only, never committed or pasted in an issue:
  - `ANDROID_SERIAL`: the phone's adb serial (scripts with an optional `[serial]` argument fall back to it).
  - `LP3_NUMBER`: the LP3's own number, for self-texts, the MMS loop and Google Voice.
  - `PEER_NUMBER`: a second phone's number, for calls out, texts to another number and the group MMS.
- Scripts named "device side" are fed to the phone's shell: `adb shell < scripts/test/<script>`.
- Call, SMS and MMS scripts send real calls and messages.

## Scripts

A blank checklist row means a support script, not a test of its own.

| Script | What it does | Checklist row | Needs |
|---|---|---|---|
| `gsi-pack-check.sh` | Pack files on the phone match the payload; density, keylayouts, overlays, `lp3-atel-ready`, IMS app, MmTel voice | Display, Keys, IMS (VoLTE) registered | `out/payload` from `scripts/build-payload.sh` |
| `gsi-volte-check.sh` | Device side: overlays, VoLTE carrier-config keys, IMS capability and registration lines | IMS (VoLTE) registered | |
| `gsi-ims-state.sh` | Device side: ImsService binding and registration on SIM slot 1 | IMS (VoLTE) registered | |
| `gsi-reg.sh` | Device side: registration summary per slot, network type, IMS registration | IMS (VoLTE) registered | |
| `gsi-call.sh` | `out <digits\|peer\|self>` places a call; `in` waits for one and answers; prints the call-log row (features 64 = VoLTE) | Call out, call in | `PEER_NUMBER` or `LP3_NUMBER` for `out` |
| `gsi-self-sms.sh` | Sends an SMS from AOSP Messaging to the own number or `peer` | SMS out | `LP3_NUMBER` / `PEER_NUMBER` |
| `gsi-sms-check.sh` | Device side: newest SMS rows (no addresses) and IMS/CS SMS log lines | SMS out, SMS in | |
| `mt-sms-test.sh` | Screen off or forced deep doze, a Google Voice text to the LP3, waits for it | SMS in (screen off) | Google Voice |
| `gsi-self-mms.sh` | Group text to the own number and `PEER_NUMBER`, sent as one MMS; waits for the received copy | MMS out, MMS in | `LP3_NUMBER`, `PEER_NUMBER` |
| `gsi-mms-image.sh` | Picture message to the own number through Messaging's picker; waits for the received copy | MMS out, MMS in | an image on the phone, `LP3_NUMBER` |
| `wait-mms.sh` | Waits for a received MMS row | MMS in | |
| `gsi-data-check.sh` | Wi-Fi off, waits for validated cellular data, pings over IPv4 and IPv6, Wi-Fi back | Mobile data | |
| `wfc-wait.sh` | Device side: waits for IMS registration over Wi-Fi (Wi-Fi Calling) | | |
| `gsi-pack-facts.sh` | Device side: build, slot, DSU, SELinux, overlays, keylayouts, IMS packages, `su`, for a bug report | | |
| `settings-pass.sh` | Opens the main Settings screens, saves their text and screenshots | | `tools/ui-dump.sh` |
| `gv/gv-tab.sh` | Prints the Google Voice tab's CDP id | | Google Voice |
| `gv/gv-text-lp3.sh` | Texts the LP3 from Google Voice | SMS in | Google Voice |
| `gv/gv-call-lp3.sh` | Calls the LP3 from Google Voice while `gsi-call.sh in` answers | Call in | Google Voice |
| `gv/gv.js`, `gv/gv-call.js`, `gv/gv-mms.js` | Drive Google Voice web over CDP: send a text, place a call, send a picture in the open thread | | Google Voice |

## Google Voice (optional)

The `gv/` scripts stand in for the second phone: they drive the Google Voice web app to text and call the LP3.
They need:

- A Google Voice account, signed in as the browser's first account (`/u/0`).
- A Chromium-family browser started with remote debugging on port 9222, for example
  `--remote-debugging-port=9222`, and a Google Voice tab open
  (`curl -X PUT 'http://127.0.0.1:9222/json/new?https://voice.google.com/u/0/'`). Anything that can reach that
  port controls the browser: use a separate browser profile and close it after the test.
- `node` 22 or newer (`--experimental-websocket`), `curl` and `jq`.
- `LP3_NUMBER` set. Calls also need the browser to have a microphone; `gv-call.js` grants the permission.
