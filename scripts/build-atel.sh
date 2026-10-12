#!/usr/bin/env bash
# Build lp3-atel-ready (atel/README.md) and stage it as a patcher payload under out/atel/payload/, mirroring the
# image root, with its own contexts.txt. Merge that tree into the payload you pass to patch-gsi.sh (append its
# contexts.txt lines to yours). Needs a JDK (javac) and the Android SDK: build-tools (d8) and the android-36 platform.
# Usage: scripts/build-atel.sh
#   env: ANDROID_HOME, BUILD_TOOLS (dir), PLATFORM (default android-36)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
sdk=${ANDROID_HOME:-$HOME/Library/Android/sdk}
die() { echo "build-atel: $*" >&2; exit 1; }
bt=${BUILD_TOOLS:-$(ls -d "$sdk"/build-tools/[0-9]*.[0-9]*.[0-9] 2>/dev/null | sort -V | tail -1 || true)}
jar=$sdk/platforms/${PLATFORM:-android-36}/android.jar
[ -x "$bt/d8" ] || die "no d8 in build-tools '$bt' (set BUILD_TOOLS)"
[ -f "$jar" ] || die "no $jar (install the platform or set PLATFORM)"
command -v javac >/dev/null || die "no javac (install a JDK 11 or newer)"

out=$root/out/atel
rm -rf "$out"; mkdir -p "$out/classes"
javac --release 11 -Xlint:all -Werror -cp "$jar" -d "$out/classes" "$root"/atel/src/lp3treble/*.java
"$bt/d8" --release --min-api 30 --lib "$jar" --output "$out/lp3-atel-ready.jar" "$out"/classes/lp3treble/*.class

p=$out/payload
install -d "$p/system/product/bin" "$p/system/product/framework" "$p/system/product/etc/init" \
  "$p/system/product/etc/selinux"
install -m 0644 "$out/lp3-atel-ready.jar" "$p/system/product/framework/lp3-atel-ready.jar"
install -m 0755 "$root/atel/lp3-atel-ready.sh" "$p/system/product/bin/lp3-atel-ready"
install -m 0644 "$root/atel/lp3-atel-ready.rc" "$p/system/product/etc/init/lp3-atel-ready.rc"
# The GSI ships both of these empty, so ours replace them whole.
install -m 0644 "$root/atel/lp3_atel.cil" "$p/system/product/etc/selinux/product_sepolicy.cil"
install -m 0644 "$root/atel/product_file_contexts" "$p/system/product/etc/selinux/product_file_contexts"
echo "/system/product/bin/lp3-atel-ready u:object_r:lp3_atel_exec:s0 0755" >"$p/contexts.txt"
(cd "$p" && find . -type f | sort)
echo "BUILT $p"
