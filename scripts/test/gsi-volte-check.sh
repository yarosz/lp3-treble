# Device side, fed to the GSI's shell: adb shell < scripts/test/gsi-volte-check.sh
# Read-only (checklist: IMS registered): lp3-treble overlays active? VoLTE keys in carrier config, IMS capability
# and registration.
cmd overlay list | grep -iE "lp3treble|carrierconfig"
dumpsys carrier_config | grep -E "carrier_volte_available_bool|hide_enhanced_4g_lte_bool|editable_enhanced_4g_lte_bool" | sort | uniq -c
dumpsys telephony.registry | grep -m2 mServiceState | sed -E 's/.*(mVoiceRegState=[^,]*).*(mOperatorAlphaLong=[^,]*).*/\1 \2/'
logcat -d | grep -E "QImsService.*(VOLTE ims registered|updateFeatureCapabilities)" | tail -3
logcat -b radio -d | grep -E "handleFeatureCapabilityChanged: (MmTel|isVolte)|setImsRegistrationState" | tail -3
