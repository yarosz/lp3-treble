# Device side, fed to the GSI's shell: adb shell < scripts/test/gsi-reg.sh
# Read-only: one-line registration summary per phone slot, the network type, and the IMS registration state.
dumpsys telephony.registry | grep -m2 mServiceState | sed -E 's/.*(mVoiceRegState=[^,]*), (mDataRegState=[^,]*).*(mOperatorAlphaLong=[^,]*).*(getRilVoiceRadioTechnology=[^,]*).*(getRilDataRadioTechnology=[^,]*).*/\1 \2 \3 \4 \5/'
getprop gsm.network.type
dumpsys telephony.registry | grep -m2 -iE "mImsReg|ImsRegistration"
logcat -b radio -d | grep -iE "IMS_REGISTRATION_STATE|ImsRegistration|reasonForDenial = [^N]|rejectCause=[1-9]" | tail -8
