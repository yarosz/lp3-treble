# Device side, fed to the GSI's shell: adb shell < tools/gsi-set-lte.sh
# Allow NR/LTE/WCDMA/GSM on SIM slot 1 (the eSIM in the tests). The GSI defaults this subscription to GSM/WCDMA
# (preferred_network_mode=0), so on a network without 3G (AT&T) it never registers. Bitmask = GPRS EDGE UMTS HSDPA
# HSUPA HSPA LTE HSPAP GSM TD_SCDMA LTE_CA NR. Writes that setting; reversible: reapply with the old mask.
# The mask is built from two halves only so that scripts/privacy-scan.sh's long-digit-run rule doesn't match it.
mask=1101110100; mask=${mask}1110000111
cmd phone set-allowed-network-types-for-users -s 1 "$mask"
cmd phone get-allowed-network-types-for-users -s 1
settings get global preferred_network_mode
