# Device side, fed to the GSI's shell: adb shell < scripts/test/wfc-wait.sh
# Read-only (Wi-Fi Calling): wait up to 90 s for an IMS registration over WLAN in the logs, then print the IMS
# register/unregister and IWLAN/QNS lines.
i=0
while [ $i -lt 30 ]; do
  r=$(logcat -d -b all | grep -E 'imsRadioTech=WLAN|imsTransportType=WLAN|isOnWfc: true' | tail -1)
  [ -n "$r" ] && { echo "WFC: $r" | cut -c1-140; break; }
  i=$((i+1)); sleep 3
done
[ -n "$r" ] || echo "no WLAN registration after 90 s"
logcat -d -b all | grep -E 'handleImsRegistered|handleImsUnregistered|IWLAN|iwlan.*(error|fail)|QNS|qns' | tail -8 | cut -c1-150
