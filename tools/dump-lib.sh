# Sourced by rollback.sh and fullflash.sh. Expects S (serial), dump (dump dir), work (prepped images) and die().
parts="super vbmeta_a boot_a"
want() { [ -s "$dump/manifest.tsv" ] && awk -F'\t' -v n="$1" '$1==n && $2=="OK" {print $5; exit}' "$dump/manifest.tsv"; }
verify() {
  local w; w=$(want "$1")
  [ -n "$w" ] || die "no OK row for $1 in $dump/manifest.tsv"
  [ -s "$work/$1.img" ] || die "$work/$1.img missing or empty (run rollback.sh prep)"
  [ "$(shasum -a 256 "$work/$1.img" | cut -d' ' -f1)" = "$w" ] || die "$1 hash mismatch"
  echo "$1 sha OK"
}
verify_all() { for p in $parts; do verify "$p"; done; }
gv() { fastboot -s "$S" getvar "$1" 2>&1 | awk -F': ' -v k="$1" '$1==k {print $2}' | tr -d '\r'; }
listed() { fastboot devices | awk -v s="$S" '$1==s {f=1} END {exit !f}'; }
wait_fb() { for i in $(seq 1 60); do listed && return 0; sleep 2; done; die "no fastboot device $S"; }
# wait_mode yes: in fastbootd (userspace). wait_mode no: in the bootloader. Polls while the old mode still answers.
wait_mode() {
  local i u
  for i in $(seq 1 60); do
    if listed; then
      u=$(gv is-userspace)
      if [ "$1" = yes ]; then [ "$u" = yes ] && return 0; else [ "$u" != yes ] && return 0; fi
    fi
    sleep 2
  done
  die "is-userspace never became $1: don't flash; get to the bootloader and run rollback.sh check"
}
to_bootloader() {
  if adb devices | grep -q "^$S	device"; then adb -s "$S" reboot bootloader; fi
  wait_fb
  [ "$(gv is-userspace)" != yes ] || { fastboot -s "$S" reboot bootloader; wait_mode no; }
}
