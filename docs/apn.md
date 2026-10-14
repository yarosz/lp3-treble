# Mobile data APNs on US Mobile

The GSI's APN list is AOSP's, and on the LP3's US Mobile line it picks an APN that doesn't give working mobile
data. `scripts/apn/set-apn.sh` adds the APN stock LightOS uses and makes it the preferred APN of the SIM that
carries mobile data. Run it while the GSI is booted: the GSI and LightOS keep separate APN lists. It uses adb
without root, and it reuses a matching, enabled APN row rather than adding a duplicate, so running it twice is
safe.

```
scripts/apn/set-apn.sh darkstar      # US Mobile Dark Star, AT&T network (310/280)
scripts/apn/set-apn.sh lightspeed    # US Mobile Light Speed, T-Mobile network (310/240)
```

It refuses when the mobile-data SIM is on another network. When it changes something, it prints an `undo:`
command: keep it. The undo deletes the row the script added and returns the APN choice to automatic. A rerun
that finds nothing to change prints `nothing changed` and no undo. You can also delete the APN in Settings >
Network & internet > SIMs > Access Point Names.

The `lightspeed` path was tested on the LP3 in the GSI. The `darkstar` path uses the same code with the values
US Mobile support gave for Dark Star; it was not run on a Dark Star SIM (the test line moved to Light Speed).

| Network | Without the script | APN it sets |
|---|---|---|
| Dark Star (AT&T) | Attaches on the default `nxtgenphone` APN, but data never validates | `ereseller`, IPv4v6, AT&T MMSC |
| Light Speed (T-Mobile) | The default `fast.t-mobile.com` APN validates, but IPv4 traffic gets no replies (see below) | `epc.tmobile.com`, IPv4, T-Mobile MMSC |

These values are the carriers' public APN settings.

## Why the pack doesn't fix this itself

APNs are not overlay resources. Patching the GSI's `apns-conf.xml` would mean carrying a modified copy of an
AOSP file per GSI build. An entry keyed only on 310/240 would also apply to every other T-Mobile MVNO SIM.

## Also check

A SIM that is new to the GSI starts with mobile data off. Turn on Settings > Network & internet > SIMs >
Mobile data, or run `adb shell svc data enable`.

On Light Speed's default APN, IPv6 and the carrier's NAT64 work, but IPv4 doesn't: the modem puts its own IPv4
address (192.0.0.8/27, the 464XLAT range) on the data interface, so Android never starts its own CLAT, and
IPv4 connections open but get no replies. Stock LightOS does the same on that APN; it ships the IPv4 APN
instead. With the script's IPv4 APN the phone gets a native IPv4 address and IPv4 works. Details are an open
item in [`LEDGER.md`](../LEDGER.md).
