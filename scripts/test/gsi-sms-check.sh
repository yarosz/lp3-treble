# Device side, fed to the GSI's shell: adb shell < scripts/test/gsi-sms-check.sh
# Read-only: the newest SMS rows without addresses (type 1=in, 2=sent, 5=failed; the body is shown) and the IMS vs
# CS SMS log lines.
content query --uri content://sms --projection _id:type:date:status:error_code:sub_id:body --sort "_id DESC" 2>&1 | head -6
logcat -b radio -d | grep -iE "ImsSmsDispatcher|sendSms|SEND_SMS|onSendSmsResult|IMS_SEND_SMS|NEW_SMS|onSmsReceived|deliverSms" | tail -10
