#!/usr/bin/env bash
# Back up user data before a wipe (bootloader unlock, full flash or rollback): media and documents, SMS, MMS (with
# parts), call log and contacts. Read-only on the phone; needs no root.
# Copies only these /sdcard folders: DCIM Pictures Movies Download Documents Recordings Music Ringtones Notifications
# Alarms Podcasts Audiobooks. Other /sdcard folders (app folders such as Android/) are not copied.
# Usage: user-data-backup.sh <serial> <outdir>   Exit 1 if any pull or query failed (listed at the end).
# The output is personal data: keep it private (backup-encrypt.sh), never publish it.
set -uo pipefail
s=${1:?serial}; out=${2:?outdir}
dirs="DCIM Pictures Movies Download Documents Recordings Music Ringtones Notifications Alarms Podcasts Audiobooks"
mkdir -p "$out/sdcard" "$out/telephony/mms-parts"
a() { adb -s "$s" shell "$@" </dev/null; }
failed=""
fail() { failed="$failed $1"; echo "FAILED $1"; }

for d in $dirs; do
  a "[ -d /sdcard/$d ]" || continue
  log=$(adb -s "$s" pull -a "/sdcard/$d" "$out/sdcard/" </dev/null 2>&1) || fail "$d"
  printf '%s\n' "$log" | tail -1
done

# Manifest of what the phone has, for verification (path<TAB>size)
a "cd /sdcard && find $dirs -type f -exec stat -c '%n	%s' {} + 2>/dev/null" | sort > "$out/phone-manifest.tsv"

a content query --uri content://sms > "$out/telephony/sms.txt" || fail sms
a content query --uri content://mms > "$out/telephony/mms.txt" || fail mms
a content query --uri content://mms/part > "$out/telephony/mms-part.txt" || fail mms-part
a "content query --uri content://mms-sms/canonical-addresses" > "$out/telephony/canonical-addresses.txt" || fail canonical-addresses
for id in $(grep -oE '^Row: [0-9]+ _id=[0-9]+' "$out/telephony/mms-part.txt" | sed 's/.*_id=//'); do
  adb -s "$s" exec-out content read --uri "content://mms/part/$id" </dev/null > "$out/telephony/mms-parts/$id" 2>/dev/null || fail "mms-part-$id"
done
a content query --uri content://call_log/calls > "$out/telephony/call-log.txt" || fail call-log
a content query --uri content://com.android.contacts/data --projection raw_contact_id:mimetype:data1:data2:data3 > "$out/telephony/contacts.txt" || fail contacts
if [ -n "$failed" ]; then echo "done with failures:$failed $(date)"; exit 1; fi
echo "done $(date)"
