#!/usr/bin/env bash
# Build the pack as a KernelSU / Magisk module zip from the image form's payload (build-payload.sh), so both forms
# ship the same files: everything under the payload's system/ except what only init uses (the launcher, the .rc
# and the SELinux files; module/service.sh does their job), and build.prop.append as system.prop.
# Usage: scripts/build-module.sh   -> out/lp3-treble-module-<version>.zip
#   env: MODULE_VERSION (default: git describe), MODULE_VERSION_CODE (default: commit count, so release builds
#   from a shallow clone must set it)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
ver=${MODULE_VERSION:-$(git -C "$root" describe --tags --always --dirty)}
code=${MODULE_VERSION_CODE:-$(git -C "$root" rev-list --count HEAD)}
sh -n "$root/module/service.sh"
"$root/scripts/build-payload.sh"
pl=$root/out/payload
m=$root/out/module
rm -rf "$m"
mkdir -p "$m"
cp -R "$pl/system" "$m/"
rm -rf "$m/system/product/bin" "$m/system/product/etc/init" "$m/system/product/etc/selinux"
rmdir "$m/system/product/etc" 2>/dev/null || true
install -m 0755 "$root/module/service.sh" "$m/service.sh"
grep -v '^#' "$pl/build.prop.append" | grep . >"$m/system.prop"
cat >"$m/module.prop" <<EOF
id=lp3_treble
name=lp3-treble
version=$ver
versionCode=$code
author=lp3-treble contributors
description=Light Phone III config for LineageOS Treble GSIs: keys, display, carrier and IMS overlays, incoming SMS fix. Unofficial, unaffiliated with Light.
EOF
# Fixed timestamps (the commit's) so two builds of one commit give the same zip.
stamp=$(git -C "$root" log -1 --format=%cd --date=format-local:%Y%m%d%H%M.%S)
find "$m" -exec touch -h -t "$stamp" {} +
zip=$root/out/lp3-treble-module-$ver.zip
rm -f "$zip"
(cd "$m" && find . -type f | sort | sed 's|^\./||' | zip -q -X "$zip" -@)
(cd "$m" && find . -type f | sort)
echo "BUILT $zip"
