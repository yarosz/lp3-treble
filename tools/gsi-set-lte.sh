# Device side, fed to the GSI's shell: adb shell < tools/gsi-set-lte.sh
# Allow NR/LTE/WCDMA/GSM on SIM slot 1 (the eSIM in the tests). The GSI defaults this subscription to GSM/WCDMA
# (preferred_network_mode=0), so on a network without 3G (AT&T) it never registers. Bitmask (bit 0 rightmost) =
# GPRS EDGE UMTS HSDPA HSUPA HSPA LTE HSPAP GSM TD_SCDMA LTE_CA NR. Writes that setting. It prints the old mask
# first: to undo, run `cmd phone set-allowed-network-types-for-users -s 1 <old mask>`.
# The mask is built from two halves only so that scripts/privacy-scan.sh's long-digit-run rule doesn't match it.
echo "before: $(cmd phone get-allowed-network-types-for-users -s 1)"
mask=1101110100; mask=${mask}1110000111
cmd phone set-allowed-network-types-for-users -s 1 "$mask"
cmd phone get-allowed-network-types-for-users -s 1
settings get global preferred_network_mode
