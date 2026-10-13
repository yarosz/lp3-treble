#!/system/bin/sh
# lp3-treble module: run lp3-atel-ready (atel/README.md) after boot and again whenever a qcril service comes
# back after a restart. A module cannot add init .rc files (init has parsed them before modules mount), so this
# late_start service script does what lp3-atel-ready.rc does in the image form. It runs as root in the root
# manager's own SELinux domain, so it needs no policy of its own.
MODDIR=${0%/*}
JAR=$MODDIR/system/product/framework/lp3-atel-ready.jar
TAG=lp3-atel

run_atel() {
  CLASSPATH=$JAR /system/bin/app_process /system/bin lp3treble.AtelReady >/dev/null 2>&1 &
}

until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 5; done

svcs=""
for s in vendor.qcrild vendor.qcrild2; do
  [ -n "$(getprop "init.svc.$s")" ] && svcs="$svcs $s"
done
# Not a Qualcomm RIL: nothing to do, and never loop.
[ -n "$svcs" ] || { log -t "$TAG" "no qcril services; lp3-atel-ready not needed"; exit 0; }

# Same triggers as lp3-atel-ready.rc: once now, then on every not-running -> running transition.
prev=""
while :; do
  cur=""
  fire=0
  for s in $svcs; do
    st=$(getprop "init.svc.$s")
    cur="$cur $s=$st"
    case "$prev" in
      "") [ "$st" = running ] && fire=1 ;;
      *" $s=running"*) ;;
      *) [ "$st" = running ] && fire=1 ;;
    esac
  done
  [ $fire = 1 ] && run_atel
  prev="$cur"
  sleep 10
done
