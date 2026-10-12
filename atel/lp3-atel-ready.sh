#!/system/bin/sh
# lp3-treble: started by init (lp3-atel-ready.rc) in the lp3_atel domain. See atel/README.md.
export CLASSPATH=/product/framework/lp3-atel-ready.jar
exec /system/bin/app_process /system/bin lp3treble.AtelReady "$@"
