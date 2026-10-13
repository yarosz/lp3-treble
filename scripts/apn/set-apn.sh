#!/usr/bin/env bash
# Add a US Mobile APN the GSI's APN list lacks and make it the preferred APN of the mobile-data SIM, over adb.
# Safe to rerun: an APN row with the same network code, APN name and protocol is reused, never duplicated.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: set-apn.sh <darkstar|lightspeed> [adb serial]

  darkstar    US Mobile Dark Star (AT&T network, 310/280): APN ereseller, IPv4v6, AT&T MMSC.
              Without it the GSI attaches but mobile data never validates.
  lightspeed  US Mobile Light Speed (T-Mobile network, 310/240): APN epc.tmobile.com, IPv4, T-Mobile MMSC.
              The GSI's default T-Mobile APN is IPv6-only and gets no IPv4 on this phone.

Runs on the phone through adb shell (no root). Prints the row it used and an undo command.
Works on the GSI and on stock LightOS.
USAGE
}

case "${1:-}" in
  darkstar)
    name=Darkstar numeric=310280 apn=ereseller proto=IPV4V6 type=default,supl,mms,fota
    mms="--bind 'mmsc:s:http\\://mmsc.mobile.att.net' --bind mmsproxy:s:proxy.mobile.att.net --bind mmsport:s:80" ;;
  lightspeed)
    name='LightSpeed epc' numeric=310240 apn=epc.tmobile.com proto=IP type=default,supl,mms
    mms="--bind 'mmsc:s:http\\://mms.msg.eng.t-mobile.com/mms/wapenc'" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 64 ;;
esac
adb=(adb)
[ -n "${2:-}" ] && adb=(adb -s "$2")

# The device script runs under the phone's /system/bin/sh. Values are fixed public carrier settings, inlined.
# content --bind splits on unescaped colons, hence http\: in the MMSC URLs.
"${adb[@]}" shell sh -s <<EOF
set -e
sub=\$(settings get global multi_sim_data_call)
case "\$sub" in ''|null|-1) echo "error: no mobile-data SIM selected" >&2; exit 1 ;; esac
# One value per SIM slot, comma-separated. An APN for another network would leave the data SIM without data.
sims=\$(getprop gsm.sim.operator.numeric)
case ",\$sims," in *",$numeric,"*) ;; *) echo "error: no SIM with network code $numeric (SIMs: \$sims)" >&2; exit 1 ;; esac
where="numeric='$numeric' AND apn='$apn' AND protocol='$proto'"
rowid() { content query --uri content://telephony/carriers --where "\$where" --projection _id | sed -n 's/.*_id=\([0-9]*\).*/\1/p' | head -1; }
id=\$(rowid)
if [ -z "\$id" ]; then
  content insert --uri content://telephony/carriers --bind name:s:'$name' --bind apn:s:$apn \
    --bind numeric:s:$numeric --bind mcc:s:${numeric:0:3} --bind mnc:s:${numeric:3} --bind type:s:$type \
    --bind protocol:s:$proto --bind roaming_protocol:s:$proto --bind carrier_enabled:i:1 --bind edited:i:1 \
    --bind user_visible:i:1 --bind user_editable:i:1 $mms
  id=\$(rowid)
  [ -n "\$id" ] || { echo "error: insert did not create a row" >&2; exit 1; }
  echo "added APN row _id=\$id ($apn, $numeric, $proto)"
  undo="content delete --uri content://telephony/carriers --where _id=\$id"
else
  echo "APN row already present: _id=\$id ($apn, $numeric, $proto)"
  undo=""
fi
uri=content://telephony/carriers/preferapn/subId/\$sub
old=\$(content query --uri \$uri --projection _id | sed -n 's/.*_id=\([0-9]*\).*/\1/p' | head -1)
if [ "\$old" = "\$id" ]; then
  echo "already the preferred APN of data SIM subId \$sub"
else
  content insert --uri \$uri --bind apn_id:i:\$id
  echo "preferred APN of data SIM subId \$sub: \${old:-none} -> \$id"
  if [ -n "\$old" ]; then
    undo="content insert --uri \$uri --bind apn_id:i:\$old\${undo:+; \$undo}"
  else
    undo="content delete --uri \$uri\${undo:+; \$undo}"
  fi
fi
content query --uri \$uri --projection _id:name:apn:protocol
if [ -n "\$undo" ]; then echo "undo: adb shell '\$undo'"; fi
EOF
