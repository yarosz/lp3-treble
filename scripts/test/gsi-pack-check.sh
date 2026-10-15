#!/usr/bin/env bash
# In a booted GSI (checklist: pack files live, display, keys, IMS): prove the pack files are live (not FEC-reverted
# to stock) and the telephony basics are up. Compares the on-device sha256 of each payload file with the payload
# dir the image was patched from. Read-only.
# Usage: gsi-pack-check.sh [serial] [payload dir]   (defaults: $ANDROID_SERIAL, out/payload from build-payload.sh)
set -uo pipefail
S=${1:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}
here=$(cd "$(dirname "$0")" && pwd -P)
pl=${2:-$here/../../out/payload}
a() { adb -s "$S" shell "$@" </dev/null | tr -d '\r'; }
fail=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
[ -d "$pl" ] || { echo "no payload dir: $pl"; exit 2; }
[ -n "$(a getprop ro.lineage.version)" ] || { echo "not in the GSI"; exit 2; }
while read -r f; do
  dev=${f#.}
  [ "$dev" = /contexts.txt ] || [ "$dev" = /build.prop.append ] && continue
  # shell may not read lp3_atel_exec; the service's own log line below proves that file.
  [ "$dev" = /system/product/bin/lp3-atel-ready ] && continue
  want=$(shasum -a 256 "$pl/$f" | cut -d' ' -f1)
  got=$(a sha256sum "$dev" 2>&1 | cut -d' ' -f1)
  [ "$got" = "$want" ] && ok "$dev matches payload" || bad "$dev: device $got, payload $want"
done < <(cd "$pl" && find . -type f | sort)
[ "$(a getprop ro.sf.lcd_density)" = 320 ] && ok "ro.sf.lcd_density 320" || bad "density $(a getprop ro.sf.lcd_density)"
[ "$(a getprop ro.telephony.default_network)" = 33,33 ] && ok "ro.telephony.default_network 33,33" || bad "default_network"
# Capture first: grep -q closing the pipe early would fail the pipeline under pipefail.
inp=$(a dumpsys input); ovl=$(a cmd overlay list); log=$(a logcat -d -b all)
grep -q 'KeyLayoutFile: /system/usr/keylayout/Pixart_pat9126ja.kl' <<<"$inp" && ok "wheel keylayout loaded" || bad "wheel keylayout"
grep -q 'KeyLayoutFile: /system/usr/keylayout/gpio-keys.kl' <<<"$inp" && ok "gpio-keys keylayout loaded" || bad "gpio-keys keylayout"
l=$(grep '\[x\].*lp3' <<<"$ovl" | tr -s ' ')
[ -n "$l" ] && ok "lp3 overlay enabled:$l" || bad "lp3 overlay not enabled"
l=$(grep ' lp3-atel *: ' <<<"$log" | tail -1)
case "$l" in *"ATEL UI ready sent to [oemhook0, oemhook1]"*) ok "lp3-atel-ready ran: ${l#*: }" ;; *) bad "lp3-atel-ready: '${l#*: }'" ;; esac
pid=$(a pidof org.codeaurora.ims); [ -n "$pid" ] && ok "org.codeaurora.ims running" || bad "org.codeaurora.ims not running"
l=$(grep 'MmTel Capabilities' <<<"$log" | tail -1)
case "$l" in *"Voice: true"*) ok "MmTel Voice true" ;; *) bad "MmTel Voice not true: ${l#*MmTel Capabilities - }" ;; esac
# DSU dm-verity: a patched block that FEC "corrected" back to stock logs verity-fec in the kernel buffer.
l=$(grep -i 'verity-fec' <<<"$log" | tail -2)
[ -z "$l" ] && ok "no verity-fec corrections in the kernel log" || bad "verity-fec: $l"
exit $fail
