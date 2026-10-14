#!/system/bin/sh
# lp3-treble module: run lp3-atel-ready (atel/README.md) after boot and again whenever a qcril process starts.
# A module cannot add init .rc files (init has parsed them before modules mount), so this late_start service
# script does what lp3-atel-ready.rc does in the image form. It runs as root in the root manager's own SELinux
# domain, so it needs no policy of its own.
MODDIR=${0%/*}
# Loaded from the module directory, not /product, so the SMS fix works even when system/ is not mounted.
JAR=$MODDIR/system/product/framework/lp3-atel-ready.jar
TAG=lp3-atel
POLL=2

until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 5; done

# The shutter is a camera key, but LineageOS only launches the camera on a long press with its camera_launch
# setting on, which has no overlayable default. Turn it on once; a value the user set later is left alone.
if ! content query --uri content://lineagesettings/system --where "name='camera_launch'" | grep -q value=; then
  content insert --uri content://lineagesettings/system --bind name:s:camera_launch --bind value:s:1
fi

# Not a Qualcomm RIL: nothing to do, and never loop.
if [ ! -e /vendor/bin/hw/qcrilNrd ] && [ ! -e /vendor/bin/qcrild ]; then
  log -t "$TAG" "no qcril binary; lp3-atel-ready not needed"
  exit 0
fi
# On KernelSU without a mounting metamodule, system/ is not mounted: the overlays and keylayouts are missing.
[ -e /product/overlay/lp3-treble-carrierconfig.apk ] ||
  log -t "$TAG" "module system/ files are not mounted (KernelSU needs a metamodule such as meta-overlayfs)"

# The .rc fires when a qcril service enters running. Watching process ids instead catches every (re)start, even
# one faster than the poll, and services that start late. A new run replaces a previous one still retrying, as
# the .rc's `restart` does.
pid=""
prev=""
while :; do
  cur=$(pidof qcrilNrd qcrild)
  if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then
    for p in $cur; do
      case " $prev " in
        *" $p "*) ;;
        *)
          [ -n "$pid" ] && kill "$pid" 2>/dev/null
          CLASSPATH=$JAR /system/bin/app_process /system/bin lp3treble.AtelReady >/dev/null 2>&1 &
          pid=$!
          break ;;
      esac
    done
  fi
  prev=$cur
  sleep $POLL
done
