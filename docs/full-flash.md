# Full flash

DSU is the safer way to try the GSI: it leaves stock LightOS untouched, and the next reboot returns to it. A
full flash replaces stock `system_a` and wipes userdata. This page is the procedure tested once on firmware
`00WW_1_440000` (see the [checklist](checklist.md)), including the rollback. Read it to the end before you
start. You do it at your own risk.

## Before you start

- Bootloader unlocked, firmware `00WW_1_440000`, current slot `a` (`fastboot getvar current-slot`).
- `fastboot getvar snapshot-update-status` in the bootloader says `none`. If an OTA is in progress, stop.
- A patched image built as in the README (`lp3.img`, raw ext4, not the `.gz`).
- Back up anything you want from LightOS: the flash and the rollback both wipe userdata.

### Back up the stock partitions

The rollback restores `super` and `vbmeta_a` from your own copies. Make them before you flash, with temporary
root: `fastboot boot` a rooted boot image built for your firmware (for example the ReSukiSU image from
[vandamd/light-guide](https://github.com/vandamd/light-guide)'s release). `fastboot boot` writes nothing to the
phone, and the next reboot returns to the stock kernel. Then, as root on the phone, copy the two partitions to
the computer and check that each copy's sha256 matches the phone's:

```
/dev/block/by-name/super      6442450944 bytes
/dev/block/by-name/vbmeta_a        65536 bytes
```

Keep the copies safe. Without them there is no rollback.

### Check the space in `super`

`lpdump` (as root) lists the partitions in `super` and their extents. The new `system_a` must fit in the
current `system_a` plus the free space after the last extent. On the test phone, `super` had about 1.7 GB free
and `system_a` was 1.5 GB, and the patched image was 3.0 GB. The six `*-cow` entries that `lpdump` lists are
leftovers from Light's last update; with snapshot status `none` they are not in use.

## Flash

1. Reboot to the bootloader (`adb reboot bootloader`) and flash the stock `vbmeta_a` with verification turned
   off. Without the flags, the stock `vbmeta_system` hash for `system` fails on the GSI.

   ```
   fastboot --disable-verity --disable-verification flash vbmeta_a vbmeta_a.img
   ```

2. Go to fastbootd and flash the image. fastbootd resizes `system_a` to fit.

   ```
   fastboot reboot fastboot
   fastboot flash system lp3.img
   ```

3. Go back to the bootloader and wipe userdata. **Don't use `fastboot -w`** (see the
   [known issues](checklist.md#known-issues)).

   ```
   fastboot reboot bootloader
   fastboot erase userdata
   fastboot erase metadata
   fastboot reboot
   ```

The GSI's `skip_mount.cfg` skips the stock `product` and `system_ext` partitions, so nothing else needs
changing. Then install the IMS app and reboot once, as in the README.

If the phone stops at "Can't load Android system. Your data may be corrupt", choose "Factory data reset". That
formats userdata the way the phone expects.

## Roll back to stock LightOS

From the bootloader, restore your two copies and wipe userdata:

```
fastboot flash super super.img
fastboot flash vbmeta_a vbmeta_a.img
fastboot getvar current-slot
fastboot erase userdata
fastboot erase metadata
fastboot reboot
```

`current-slot` must still say `a`. fastboot splits the 6 GiB `super` image into chunks on its own. LightOS
boots into its setup screens. After the wipe, turn Developer Mode on again (dial `*7412369#` in the Phone tool)
to get adb back, and check that LightOS's update service is still the way you want it.
