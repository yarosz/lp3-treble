# Full flash

DSU is the safer way to try the GSI: it leaves stock LightOS untouched, and the next reboot returns to it. A
full flash replaces stock `system_a` and wipes userdata. This page describes a procedure tested once, on
firmware `00WW_1_440000`, slot `a`, including the rollback (see the [checklist](checklist.md)). Read it to the
end before you start. You do it at your own risk.

## Before you start

- Bootloader unlocked, firmware `00WW_1_440000`.
- Current slot `a`: `fastboot getvar current-slot` in the bootloader. **If it says `b`, stop.** Every command
  here writes slot `a`, and only slot `a` was tested.
- `fastboot getvar snapshot-update-status` in the bootloader says `none` (tested there). If an update is in
  progress, stop. Turn off LightOS updates before you make the backup, and take no update until you have rolled
  back: the rollback restores the partitions as they were at backup time.
- A recent platform-tools (fastboot with fastbootd support), a charged phone and a direct USB cable. Restoring
  `super` sends 6 GiB.
- A way to reach the bootloader without adb. There is no documented button combination for the LP3 yet. If the
  flashed system fails to boot and you can't reach the bootloader, you can't run the rollback.
- A patched image built as in the README (`lp3.img`, raw ext4, not the `.gz`).
- Back up anything you want from LightOS: the flash and the rollback both wipe userdata. eSIM profiles live on
  the SIM chip and survived both wipes in the test.

### Back up the stock partitions

The rollback restores `super`, `vbmeta_a` and `boot_a` from your own copies. `boot_a` isn't written by this
flash, but an installer such as vandamd/light-guide's writes its own kernel there, so keep the stock one too. Make
the copies before you flash. The same steps are scripted in [`tools/`](../tools/README.md) (`partition-dump.sh`,
`verify-dump.sh`, `fullflash.sh`, `rollback.sh`). You need root
for one boot: `fastboot boot` a rooted boot image built for `00WW_1_440000`. The test used `resukisu-boot.img`
from vandamd/light-guide's `lightos-resukisu-susfs-00WW_1_440000-preview1` release, sha256
`820e91e882af25a9174dd23a4caea70412fdf97159f951ab0df9b2e531760fe9`. `fastboot boot` writes nothing to the phone,
and the next reboot returns to the stock kernel. With LightOS booted on that kernel, and `su` granted to the adb
shell in the root manager app:

```
adb exec-out "su -c 'dd if=/dev/block/by-name/super bs=4194304 2>/dev/null'" > super.img
adb exec-out "su -c 'dd if=/dev/block/by-name/vbmeta_a 2>/dev/null'" > vbmeta_a.img
adb exec-out "su -c 'dd if=/dev/block/by-name/boot_a bs=4194304 2>/dev/null'" > boot_a.img
adb shell "su -c 'sha256sum /dev/block/by-name/super /dev/block/by-name/vbmeta_a /dev/block/by-name/boot_a'"
shasum -a 256 super.img vbmeta_a.img boot_a.img
```

The hashes must match, and the files must be exactly 6442450944, 65536 and 100663296 bytes. Don't flash anything until
they do. Keep the copies safe, and don't share or upload them: they contain Light's software.

### Check the space in `super`

`lpdump` (as root) lists the partitions in `super`, their extents and the group size limits. The new `system_a`
must fit in the current `system_a` plus all the free space in `super`, and the group
`qti_dynamic_partitions_a` must stay under its maximum size. On the test phone, `super` had about 1.7 GB free
and `system_a` was 1.5 GB, and the patched image was 3.0 GB. **If it doesn't fit, stop.** Don't delete logical
partitions: that was not tested. The six `*-cow` entries in `lpdump` are leftovers from Light's last update; with
snapshot status `none` they are not in use.

## Flash

1. Reboot to the bootloader (`adb reboot bootloader`) and flash your stock `vbmeta_a` with verification turned
   off. Without the flags, the stock `vbmeta_system` hash for `system` fails on the GSI.

   ```
   fastboot --disable-verity --disable-verification flash vbmeta_a vbmeta_a.img
   ```

2. Go to fastbootd, check the slot again, and flash the image. fastbootd resizes `system_a` to fit.

   ```
   fastboot reboot fastboot
   fastboot getvar current-slot
   fastboot flash system_a lp3.img
   ```

3. Go back to the bootloader and wipe userdata. **Don't use `fastboot -w`** (see the
   [known issues](checklist.md#known-issues)).

   ```
   fastboot reboot bootloader
   fastboot erase userdata
   fastboot erase metadata
   fastboot reboot
   ```

   In the test, userdata was wiped with `fastboot -w`, and the first boot stopped at "Can't load Android
   system. Your data may be corrupt". "Factory data reset" on that screen fixed it. The erase commands above
   were tested only on the rollback, where LightOS formatted the blank partitions itself; the GSI uses the same
   vendor settings, so it should do the same. If you see that screen anyway, choose "Factory data reset".

The GSI's `skip_mount.cfg` skips the stock `product` and `system_ext` partitions, so nothing else needs
changing. In the GSI, install the IMS app from phh's Treble settings (IMS section), then reboot once. Turn on
mobile data, and set the APN if your carrier needs it ([APNs](apn.md)).

## Roll back to stock LightOS

From the bootloader, check the slot, restore your three copies and wipe userdata:

```
fastboot getvar current-slot
fastboot flash super super.img
fastboot flash vbmeta_a vbmeta_a.img
fastboot flash boot_a boot_a.img
fastboot erase userdata
fastboot erase metadata
fastboot reboot
```

`current-slot` must say `a`. If it says `b` (for example after the flashed system failed to boot several times),
`fastboot --set-active=a` switches back; this step was not needed in the test. Don't flash any `_b` partition.
fastboot splits the 6 GiB `super` image into chunks on its own; restoring `super` puts back every logical
partition, whatever the flash changed. LightOS boots into its setup screens. After the wipe, turn Developer Mode
on again (dial `*7412369#` in the Phone tool) to get adb back, and turn LightOS updates off again if you had
them off: the wipe turns them back on.
