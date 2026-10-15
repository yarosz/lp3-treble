# Device side, fed to the GSI's shell: adb shell < scripts/test/gsi-ims-state.sh
# Read-only: is the ImsService bound and registered on SIM slot 1 (the eSIM in the tests)?
echo "== resolver"; dumpsys telephony_ims 2>/dev/null | grep -iE "ImsResolver|bound|org.codeaurora|ImsServiceController|isBound|feature" | head -20
echo "== registration"; cmd phone ims get-ims-service -s 1 -d 2>&1
dumpsys telephony.registry | grep -iE "ImsReg|imsRegistration" | head -4
echo "== radio ims"; logcat -b radio -d | grep -iE "ImsPhone|IMS_REG|ImsManager|ImsService|registrationState|onRegistered|onDeregistered" | tail -15
echo "== main ims"; logcat -d | grep -iE "org.codeaurora.ims|ImsService|imsradio|QtiIms|ImsSenderRxr" | tail -20
