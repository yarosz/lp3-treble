#!/usr/bin/env bash
# Back up user data before a wipe (bootloader unlock, full flash or rollback): media and documents, SMS, MMS (with
# parts), call log and contacts. Read-only on the phone; needs no root.
# Usage: user-data-backup.sh <serial> <outdir>
# The output is personal data: keep it private (backup-encrypt.sh), never publish it.
set -uo pipefail
s=${1:?serial}; out=${2:?outdir}
mkdir -p "$out/sdcard" "$out/telephony/mms-parts"
a() { adb -s "$s" shell "$@" </dev/null; }

for d in DCIM Pictures Movies Download Documents Recordings Music Ringtones Notifications Alarms Podcasts Audiobooks; do
  a "[ -d /sdcard/$d ]" && adb -s "$s" pull -a "/sdcard/$d" "$out/sdcard/" </dev/null | tail -1
done

# Manifest of what the phone has, for verification (path<TAB>size)
a "cd /sdcard && find DCIM Pictures Movies Download Documents Recordings Music Ringtones Notifications Alarms Podcasts Audiobooks -type f -exec stat -c '%n	%s' {} + 2>/dev/null" | sort > "$out/phone-manifest.tsv"

a content query --uri content://sms > "$out/telephony/sms.txt"
a content query --uri content://mms > "$out/telephony/mms.txt"
a content query --uri content://mms/part > "$out/telephony/mms-part.txt"
a "content query --uri content://mms-sms/canonical-addresses" > "$out/telephony/canonical-addresses.txt"
for id in $(grep -oE '^Row: [0-9]+ _id=[0-9]+' "$out/telephony/mms-part.txt" | sed 's/.*_id=//'); do
  adb -s "$s" exec-out content read --uri "content://mms/part/$id" </dev/null > "$out/telephony/mms-parts/$id" 2>/dev/null
done
a content query --uri content://call_log/calls > "$out/telephony/call-log.txt"
a content query --uri content://com.android.contacts/data --projection raw_contact_id:mimetype:data1:data2:data3 > "$out/telephony/contacts.txt"
echo "done $(date)"
