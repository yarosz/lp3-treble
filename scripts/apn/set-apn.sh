#!/usr/bin/env bash
# Add a US Mobile APN the GSI's APN list lacks and make it the preferred APN of the mobile-data SIM, over adb.
# Safe to rerun: a usable APN row with the same network code, APN name and protocol is reused, never duplicated.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: set-apn.sh <darkstar|lightspeed> [adb serial]

  darkstar    US Mobile Dark Star (AT&T network, 310/280): APN ereseller, IPv4v6, AT&T MMSC.
              Without it the GSI attaches but mobile data never validates.
  lightspeed  US Mobile Light Speed (T-Mobile network, 310/240): APN epc.tmobile.com, IPv4, T-Mobile MMSC.
              On the GSI's default T-Mobile APN, IPv4 connections get no replies on this phone.

Run it while the GSI is booted (APNs are per OS; it also works on stock LightOS). It uses adb shell, no root.
It changes only the SIM that carries mobile data, and refuses if that SIM is on another network.
When it changes something it prints an undo command: keep it.
USAGE
}

# content --bind splits on unescaped colons, hence http\: in the MMSC URLs.
case "${1:-}" in
  darkstar)
    name=Darkstar numeric=310280 apn=ereseller proto=IPV4V6 type=default,supl,mms,fota
    mmsc='http\://mmsc.mobile.att.net' mmsproxy=proxy.mobile.att.net mmsport=80 ;;
  lightspeed)
    name='LightSpeed epc' numeric=310240 apn=epc.tmobile.com proto=IP type=default,supl,mms
    mmsc='http\://mms.msg.eng.t-mobile.com/mms/wapenc' mmsproxy='' mmsport='' ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 64 ;;
esac
adb=(adb)
[ -n "${2:-}" ] && adb=(adb -s "$2")

# The phone's /system/bin/sh runs a preamble of host values (none contains a single quote), then the quoted body.
{
  for v in name numeric apn proto type mmsc mmsproxy mmsport; do printf "%s='%s'\n" "$v" "${!v}"; done
  printf "adbcmd='%s'\n" "${adb[*]}"
  cat <<'EOF'
set -e
sub=$(settings get global multi_sim_data_call)
case "$sub" in ''|null|-1)
  echo "error: no SIM is selected for mobile data (Settings > Network & internet > SIMs)" >&2; exit 1 ;;
esac
# The data SIM's own network code, from its subscription record.
# grep reads the whole dump (no -m1), so dumpsys doesn't hit a closed pipe.
info=$(dumpsys isub | grep "SubscriptionInfoInternal: id=$sub " | head -1)
mcc=$(echo "$info" | sed -n 's/.* mcc=\([0-9]*\) .*/\1/p')
mnc=$(echo "$info" | sed -n 's/.* mnc=\([0-9]*\) .*/\1/p')
if [ "$mcc$mnc" != "$numeric" ]; then
  echo "error: the mobile-data SIM (subId $sub) is on ${mcc:-?}/${mnc:-?}, not ${numeric%???}/${numeric#???}" >&2
  exit 1
fi
where="numeric='$numeric' AND apn='$apn' AND protocol='$proto' AND carrier_enabled=1 AND type LIKE '%default%'"
where="$where AND (mvno_type IS NULL OR mvno_type='')"
rowid() { content query --uri content://telephony/carriers --where "$where" --projection _id | sed -n 's/.*_id=\([0-9]*\).*/\1/p' | head -1; }
undo=""
id=$(rowid)
if [ -z "$id" ]; then
  set -- --bind "name:s:$name" --bind "apn:s:$apn" --bind "numeric:s:$numeric" --bind "mcc:s:$mcc" \
    --bind "mnc:s:$mnc" --bind "type:s:$type" --bind "protocol:s:$proto" --bind "roaming_protocol:s:$proto" \
    --bind carrier_enabled:i:1 --bind edited:i:1 --bind user_visible:i:1 --bind user_editable:i:1 \
    --bind "mmsc:s:$mmsc"
  [ -n "$mmsproxy" ] && set -- "$@" --bind "mmsproxy:s:$mmsproxy" --bind "mmsport:s:$mmsport"
  content insert --uri content://telephony/carriers "$@"
  id=$(rowid)
  [ -n "$id" ] || { echo "error: insert did not create a row" >&2; exit 1; }
  undo="content delete --uri content://telephony/carriers --where _id=$id"
  echo "added APN row _id=$id ($apn, $numeric, $proto)"
  echo "undo so far: $adbcmd shell '$undo'"
else
  echo "APN row already present: _id=$id ($apn, $numeric, $proto)"
fi
uri=content://telephony/carriers/preferapn/subId/$sub
pref() { content query --uri "$uri" --projection _id | sed -n 's/.*_id=\([0-9]*\).*/\1/p' | head -1; }
old=$(pref)
if [ "$old" = "$id" ]; then
  echo "already the preferred APN of data SIM subId $sub"
else
  content insert --uri "$uri" --bind "apn_id:i:$id"
  now=$(pref)
  [ "$now" = "$id" ] || { echo "error: preferred APN is ${now:-none}, not $id, after setting it" >&2; exit 1; }
  echo "preferred APN of data SIM subId $sub: ${old:-none} -> $id"
  # Undo returns the choice to automatic rather than re-setting $old: the provider ignores a preferred APN that
  # isn't in this SIM's list, and the GSI's automatic pick can be such a row (another T-Mobile network code).
  undo="content delete --uri $uri${undo:+; $undo}"
fi
content query --uri "$uri" --projection _id:name:apn:protocol
if [ -n "$undo" ]; then echo "undo: $adbcmd shell '$undo'"; else echo "nothing changed"; fi
EOF
} | "${adb[@]}" shell sh -s
