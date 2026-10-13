#!/usr/bin/env bash
# Build the pack as a KernelSU / Magisk module zip from the same sources as the image form: the overlays, the
# keylayouts, props/product.prop (as system.prop) and lp3-atel-ready (jar + module/service.sh instead of the init
# .rc and SELinux files). Needs what build-overlays.sh and build-atel.sh need.
# Usage: scripts/build-module.sh   -> out/lp3-treble-module-<version>.zip
#   env: MODULE_VERSION (default: git describe), MODULE_VERSION_CODE (default: commit count)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
ver=${MODULE_VERSION:-$(git -C "$root" describe --tags --always --dirty)}
code=${MODULE_VERSION_CODE:-$(git -C "$root" rev-list --count HEAD)}
rm -rf "$root/out/overlays"
"$root/scripts/build-overlays.sh"
"$root/scripts/build-atel.sh"
m=$root/out/module
rm -rf "$m"
install -d "$m/system/product/overlay" "$m/system/product/framework" "$m/system/usr/keylayout"
install -m 0644 "$root"/out/overlays/*.apk "$m/system/product/overlay/"
install -m 0644 "$root/out/atel/lp3-atel-ready.jar" "$m/system/product/framework/"
install -m 0644 "$root"/keylayout/*.kl "$m/system/usr/keylayout/"
install -m 0755 "$root/module/service.sh" "$m/service.sh"
grep -v '^#' "$root/props/product.prop" | grep . >"$m/system.prop"
cat >"$m/module.prop" <<EOF
id=lp3_treble
name=lp3-treble
version=$ver
versionCode=$code
author=lp3-treble contributors
description=Light Phone III config for LineageOS Treble GSIs: keys, display, carrier and IMS overlays, incoming SMS fix. Unofficial, unaffiliated with Light.
EOF
zip=$root/out/lp3-treble-module-$ver.zip
rm -f "$zip"
(cd "$m" && find . -type f | sort | sed 's|^\./||' | zip -q -X "$zip" -@)
(cd "$m" && find . -type f | sort)
echo "BUILT $zip"
