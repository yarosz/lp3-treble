# Device side, fed to the GSI's shell: adb shell < scripts/test/gsi-pack-facts.sh
# Read-only facts about a booted GSI, for a bug report or a full-flash check: build, slot, DSU or not, SELinux,
# density, lp3 overlays, keylayouts, the camera-key setting, lp3-atel-ready, IMS/phh packages and whether su works.
echo "lineage=$(getprop ro.lineage.version) vendor=$(getprop ro.vendor.build.version.incremental) kernel=$(uname -r) slot=$(getprop ro.boot.slot_suffix) dsu=$(getprop ro.gsid.image_running) selinux=$(getenforce)"
echo "density: $(wm density | tr '\n' ' ')"
cmd overlay list | grep -i lp3
dumpsys input | grep -o 'KeyLayoutFile: [^ ]*\(gpio-keys\|Pixart\)[^ ]*' | sort -u
echo "camera_launch=$(content query --uri content://lineagesettings/system --where "name='camera_launch'" --projection value 2>/dev/null)"
pm list features | grep -c credentials
ls /system/product/framework/lp3-atel-ready.jar
getprop | grep -i -E "persist.sys.phh.ims|ro.lp3" | head -5
pm list packages | grep -i -E "ims|phh|microg|gms|resukisu" | sort
echo id | su 2>&1 | head -1
