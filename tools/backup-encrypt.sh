#!/usr/bin/env bash
# macOS only. Put backups (user-data-backup.sh, partition-dump.sh output) into one AES-256 encrypted sparse bundle,
# then verify every file's sha256 inside it. The passphrase comes from a hidden macOS dialog (typed twice) and goes
# straight to hdiutil on stdin: it never reaches a command line, log or transcript. Keep it in a password manager.
# Usage: backup-encrypt.sh <bundle path> <source dir>...   Writes the bundle only; the sources are left as they are.
set -euo pipefail
bundle=${1:?bundle}; shift
[ ! -e "$bundle" ] || { echo "exists: $bundle" >&2; exit 64; }
ask() {
  osascript -e "text returned of (display dialog \"$1\" default answer \"\" with hidden answer buttons {\"Cancel\",\"OK\"} default button \"OK\" with title \"LP3 backup encryption\")"
}
p1=$(ask "Passphrase for the LP3 backup image (save it in your password manager):")
p2=$(ask "Type the same passphrase again:")
[ -n "$p1" ] && [ "$p1" = "$p2" ] || { echo "passphrases empty or different" >&2; exit 1; }
need=$(du -sk "$@" | awk '{s+=$1} END {print int(s/1024*1.2)+512}')
printf '%s' "$p1" | hdiutil create -size "${need}m" -type SPARSEBUNDLE -fs APFS -encryption AES-256 -stdinpass \
  -volname LP3-backup "$bundle" >/dev/null
mnt=$(printf '%s' "$p1" | hdiutil attach -stdinpass -nobrowse "$bundle" | awk -F'\t' '/\/Volumes\// {print $NF}' | tail -1)
unset p1 p2
[ -d "$mnt" ] || { echo "attach failed" >&2; exit 1; }
for d in "$@"; do rsync -a "$d" "$mnt/"; done
# verify: every file's size and sha256 match the source
bad=0
for d in "$@"; do
  base=$(basename "$d")
  (cd "$d" && find . -type f -print0 | xargs -0 shasum -a 256) | sort -k2 > /tmp/lp3enc.src.$$
  (cd "$mnt/$base" && find . -type f -print0 | xargs -0 shasum -a 256) | sort -k2 > /tmp/lp3enc.dst.$$
  if cmp -s /tmp/lp3enc.src.$$ /tmp/lp3enc.dst.$$; then echo "verified $base ($(wc -l < /tmp/lp3enc.src.$$) files)"; else echo "MISMATCH $base"; bad=1; fi
  rm -f /tmp/lp3enc.src.$$ /tmp/lp3enc.dst.$$
done
hdiutil detach "$mnt" >/dev/null
echo "bundle: $bundle ($(du -sh "$bundle" | cut -f1)) bad=$bad"
exit $bad
