#!/usr/bin/env bash
# Build every RRO under overlays/<name>/ into out/overlays/lp3-treble-<name>.apk, ready to copy into the patcher's
# payload/system/product/overlay/. Needs the Android SDK: build-tools and the android-36 platform. Signed with the
# debug key by default: preinstalled overlays in /system/product/overlay don't need a platform signature.
# Usage: scripts/build-overlays.sh
#   env: LP3_EXPERIMENTAL=1 also builds overlays-experimental/<name>/ (off by default; see docs/checklist.md),
#        ANDROID_HOME, BUILD_TOOLS (dir), PLATFORM (default android-36),
#        SIGN_KEYSTORE, SIGN_ALIAS, SIGN_PASS (default: ~/.android/debug.keystore, androiddebugkey, android)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
sdk=${ANDROID_HOME:-$HOME/Library/Android/sdk}
die() { echo "build-overlays: $*" >&2; exit 1; }
# Release build-tools only (36.0.0, not 36.0.0-rc1).
bt=${BUILD_TOOLS:-$(ls -d "$sdk"/build-tools/[0-9]*.[0-9]*.[0-9] 2>/dev/null | sort -V | tail -1 || true)}
jar=$sdk/platforms/${PLATFORM:-android-36}/android.jar
ks=${SIGN_KEYSTORE:-$HOME/.android/debug.keystore}
alias=${SIGN_ALIAS:-androiddebugkey}
pass=${SIGN_PASS:-android}
for tool in aapt2 zipalign apksigner; do [ -x "$bt/$tool" ] || die "no $tool in build-tools '$bt' (set BUILD_TOOLS)"; done
[ -f "$jar" ] || die "no $jar (install the platform or set PLATFORM)"
if [ ! -f "$ks" ] && [ -z "${SIGN_KEYSTORE:-}" ]; then
  keytool -genkeypair -keystore "$ks" -alias "$alias" -storepass "$pass" -keypass "$pass" -keyalg RSA -keysize 2048 \
    -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1 || die "could not create $ks"
fi
[ -f "$ks" ] || die "no keystore $ks"

out=$root/out/overlays
mkdir -p "$out"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
dirs=("$root"/overlays/*/)
[ "${LP3_EXPERIMENTAL:-}" != 1 ] || dirs+=("$root"/overlays-experimental/*/)
for dir in "${dirs[@]}"; do
  name=$(basename "$dir"); apk=$out/lp3-treble-$name.apk
  rm -f "$apk" "$apk.idsig" "$tmp"/*
  "$bt/aapt2" compile --dir "${dir}res" -o "$tmp/res.zip"
  # --keep-raw-values: CarrierConfig reads mcc/mnc as strings; a typed int would turn an mnc like "070" into "70".
  "$bt/aapt2" link --keep-raw-values --min-sdk-version 34 --target-sdk-version 36 -I "$jar" \
    --manifest "${dir}AndroidManifest.xml" -o "$tmp/unsigned.apk" "$tmp/res.zip"
  "$bt/zipalign" -f -p 4 "$tmp/unsigned.apk" "$tmp/aligned.apk"
  "$bt/apksigner" sign --ks "$ks" --ks-key-alias "$alias" --ks-pass "pass:$pass" --key-pass "pass:$pass" \
    --v4-signing-enabled false --out "$apk" "$tmp/aligned.apk"
  echo "BUILT $apk"
done
