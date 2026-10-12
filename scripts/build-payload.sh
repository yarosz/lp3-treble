#!/usr/bin/env bash
# Build the whole pack and assemble it as a patch-gsi.sh payload in out/payload/: the overlays, lp3-atel-ready and
# props/product.prop. Needs what build-overlays.sh and build-atel.sh need (Android SDK, JDK).
# Usage: scripts/build-payload.sh
# Then: BUILD_PROP_PATH=/system/product/etc/build.prop scripts/patch-gsi.sh system.img lp3.img out/payload
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
# Start clean so a renamed or deleted overlay doesn't ship its old APK.
rm -rf "$root/out/overlays"
"$root/scripts/build-overlays.sh"
"$root/scripts/build-atel.sh"
pl=$root/out/payload
rm -rf "$pl"
mkdir -p "$pl/system/product/overlay"
cp "$root"/out/overlays/*.apk "$pl/system/product/overlay/"
cp -R "$root/out/atel/payload/system" "$pl/"
cp "$root/out/atel/payload/contexts.txt" "$pl/contexts.txt"
cp "$root/props/product.prop" "$pl/build.prop.append"
echo "payload: $pl"
(cd "$pl" && find . -type f | sort)
echo
echo "next: BUILD_PROP_PATH=/system/product/etc/build.prop scripts/patch-gsi.sh <system.img> <out.img> $pl"
