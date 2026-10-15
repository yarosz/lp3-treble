# Device side, fed to the phone's shell: adb shell < tools/dsu-oneshot.sh
# Arm the installed DSU image for the next boot only; the reboot after that returns to stock LightOS.
gsi_tool enable --single-boot
gsi_tool status
