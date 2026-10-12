#!/usr/bin/env bash
# Offline check that atel/lp3_atel.cil compiles against a GSI's platform policy and your phone's vendor policy, the
# way init compiles it at boot. A policy that fails to compile stops the phone booting the GSI, so run this before
# installing a new GSI build. Needs docker (network for apk/apt on each run). Nothing touches a device.
#
# Usage: scripts/check-sepolicy.sh <GSI system.img> <vendor policy dir> [product cil]
#   vendor policy dir: plat_pub_versioned.cil, vendor_sepolicy.cil and plat_sepolicy_vers.txt from the phone, e.g.
#     for f in plat_pub_versioned.cil vendor_sepolicy.cil plat_sepolicy_vers.txt; do
#       adb pull /vendor/etc/selinux/$f vendor-policy/; done
# Exit: 0 compiles and adds no neverallow violation, 1 fails, 64 usage, 69 docker unavailable.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"
if [ $# -lt 2 ] || [ $# -gt 3 ]; then sed -n '2,10p' "$0" >&2; exit 64; fi
img=$1; vend=$2; prod=${3:-$here/../atel/lp3_atel.cil}
for f in plat_pub_versioned.cil vendor_sepolicy.cil plat_sepolicy_vers.txt; do
  [ -s "$vend/$f" ] || { echo "error: $vend/$f missing" >&2; exit 64; }
done
[ -f "$img" ] && [ -f "$prod" ] || { echo "error: image or product cil not found" >&2; exit 64; }
img_abs=$(abspath "$(dirname "$img")")/$(basename "$img")
vend_abs=$(abspath "$vend"); prod_abs=$(abspath "$(dirname "$prod")")/$(basename "$prod")
require_shared "GSI image" "$img_abs"; require_shared "vendor policy dir" "$vend_abs"
require_shared "product cil" "$prod_abs"
need_docker
ver=$(tr -d ' \r\n' <"$vend_abs/plat_sepolicy_vers.txt")
work=$(mktemp -d "${LP3_TEST_TMP:-$HOME/.cache}/lp3-sepolicy.XXXXXX"); trap 'rm -rf "$work"' EXIT

echo "== extract platform policy (mapping $ver)"
docker run --rm -v "$(dirname "$img_abs")":/img:ro -v "$work":/out "$ALPINE_IMAGE" sh -c '
  apk add --no-cache '"$E2FSPROGS_PKG $E2FSPROGS_EXTRA_PKG"' >/dev/null
  i=/img/$1; v=$2
  for f in /system/etc/selinux/plat_sepolicy.cil /system/etc/selinux/mapping/$v.cil \
    /system/etc/selinux/mapping/$v.compat.cil /system/system_ext/etc/selinux/system_ext_sepolicy.cil \
    /system/system_ext/etc/selinux/mapping/$v.cil /system/product/etc/selinux/mapping/$v.cil; do
    n=$(echo "$f" | tr / _); debugfs -R "dump $f /out/$n" "$i" 2>/dev/null
  done' sh "$(basename "$img_abs")" "$ver"

echo "== compile (with and without our policy)"
# Debian trixie's libsepol predates two Android 16 policy capabilities; they don't affect type checks.
docker run --rm -v "$work":/w -v "$vend_abs":/v:ro -v "$prod_abs":/prod.cil:ro debian:trixie-slim sh -c '
  set -e
  apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq secilc >/dev/null 2>&1
  v=$1; s=/w/_system_etc_selinux
  grep -v "^(policycap \(functionfs_seclabel\|memfd_class\))" ${s}_plat_sepolicy.cil >/w/plat.cil
  printf "\n" >/w/empty.cil
  files() { for f in /w/plat.cil ${s}_mapping_$v.cil ${s}_mapping_$v.compat.cil \
      /w/_system_system_ext_etc_selinux_system_ext_sepolicy.cil /w/_system_system_ext_etc_selinux_mapping_$v.cil \
      "$1" /w/_system_product_etc_selinux_mapping_$v.cil /v/plat_pub_versioned.cil /v/vendor_sepolicy.cil; do
      [ -s "$f" ] || [ "$f" = "$1" ] && echo "$f"; done; }
  # As init does (-N: no neverallow checks). This is what decides whether the phone boots.
  secilc -m -M true -G -N -c 30 -o /w/p -f /dev/null $(files /prod.cil) || { echo "FAIL: does not compile"; exit 1; }
  echo "compiles as init does"
  # Neverallows: stock policy already has some; ours must add none.
  base=$(secilc -m -M true -G -c 30 -o /w/p -f /dev/null $(files /w/empty.cil) 2>&1 | grep -c "neverallow check failed" || true)
  ours=$(secilc -m -M true -G -c 30 -o /w/p -f /dev/null $(files /prod.cil) 2>&1 | grep -c "neverallow check failed" || true)
  echo "neverallow failures: stock $base, with ours $ours"
  [ "$ours" -le "$base" ] || { echo "FAIL: our policy adds neverallow violations"; exit 1; }
  echo OK' sh "$ver"
