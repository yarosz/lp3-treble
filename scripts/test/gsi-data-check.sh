#!/usr/bin/env bash
# Mobile-data check in the GSI (checklist: mobile data): Wi-Fi off, wait for a VALIDATED cellular default network,
# ping out, Wi-Fi back to its previous state. Turns mobile data on if it is off (a fresh GSI userdata starts with
# it off) and leaves it on. Usage: gsi-data-check.sh [serial]   (default: $ANDROID_SERIAL)
# Exit 0 = cellular validated and ping OK.
set -uo pipefail
S=${1:-${ANDROID_SERIAL:?pass the serial or set ANDROID_SERIAL}}
a() { adb -s "$S" shell "$@" </dev/null | tr -d '\r'; }
wifi_was=$(a settings get global wifi_on)
md=$(a settings get global mobile_data)
echo "mobile_data=$md wifi_on=$wifi_was"
restore_wifi() { if [ "$wifi_was" = 1 ]; then a svc wifi enable; fi; }
trap restore_wifi EXIT
trap 'exit 130' INT TERM
[ "$md" = 1 ] || { a svc data enable; echo "mobile data was off: turned on ($(a settings get global mobile_data))"; }
a svc wifi disable
ok=1
for _ in $(seq 1 45); do
  def=$(a dumpsys connectivity | grep -A3 -m1 'Active default network' )
  caps=$(a dumpsys connectivity | grep -m1 -E 'NetworkAgentInfo.*CELLULAR')
  case "$caps" in *VALIDATED*) ok=0; break;; esac
  sleep 2
done
echo "cellular agent: $(grep -oE 'Transports: [A-Z|]+|VALIDATED|INTERNET|NOT_METERED|TEMPORARILY_NOT_METERED' <<<"$caps" | sort -u | tr '\n' ' ')"
echo "default: $(tr '\n' ' ' <<<"$def")"
p=$(a ping -c 3 -W 5 1.1.1.1 | tail -2 | tr '\n' ' ')
echo "ping v4: $p"
# T-Mobile is IPv6-only (464XLAT): shell's IPv4 ping may fail there while data works, so either family passes.
p6=$(a ping6 -c 3 -W 5 2606:4700:4700::1111 | tail -2 | tr '\n' ' ')
echo "ping v6: $p6"
case "$p $p6" in *" 0% packet loss"*) ;; *) ok=1;; esac
[ $ok = 0 ] && echo "PASS mobile data (cellular VALIDATED, ping OK)" || echo "FAIL mobile data"
exit $ok
