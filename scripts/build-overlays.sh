#!/usr/bin/env bash
# Build every RRO under overlays/<name>/ into out/overlays/lp3-treble-<name>.apk.
# Needs the Android SDK (build-tools and a platform android.jar). The APKs are signed with the debug key: preinstalled
# overlays in /system/product/overlay don't need a platform signature.
# Usage: scripts/build-overlays.sh   (env: ANDROID_HOME, BUILD_TOOLS, PLATFORM_JAR, SIGN_KEYSTORE)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
sdk=${ANDROID_HOME:-$HOME/Library/Android/sdk}
bt=${BUILD_TOOLS:-$(ls -d "$sdk"/build-tools/* | sort -V | tail -1)}
jar=${PLATFORM_JAR:-$(ls -d "$sdk"/platforms/android-*/android.jar | sort -V | tail -1)}
ks=${SIGN_KEYSTORE:-$HOME/.android/debug.keystore}
out=$root/out/overlays
mkdir -p "$out"
for dir in "$root"/overlays/*/; do
  name=$(basename "$dir"); tmp=$(mktemp -d)
  "$bt/aapt2" compile --dir "$dir/res" -o "$tmp/res.zip"
  # --keep-raw-values: CarrierConfig reads mcc/mnc as strings; a typed int would turn mnc "080" into "80".
  "$bt/aapt2" link --keep-raw-values -I "$jar" --manifest "$dir/AndroidManifest.xml" -o "$tmp/unsigned.apk" "$tmp/res.zip"
  "$bt/zipalign" -f -p 4 "$tmp/unsigned.apk" "$tmp/aligned.apk"
  "$bt/apksigner" sign --ks "$ks" --ks-pass pass:android --out "$out/lp3-treble-$name.apk" "$tmp/aligned.apk"
  rm -rf "$tmp"
  echo "BUILT $out/lp3-treble-$name.apk"
done
