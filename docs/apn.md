# Mobile data APNs on US Mobile

The GSI's APN list is AOSP's, and on the LP3's US Mobile line it picks an APN that doesn't give working mobile
data. `scripts/apn/set-apn.sh` adds the APN stock LightOS uses and makes it the preferred APN of the SIM that
carries mobile data. It runs over adb without root, and it reuses a matching APN row rather than adding a
duplicate, so running it twice is safe.

```
scripts/apn/set-apn.sh darkstar      # US Mobile Dark Star, AT&T network (310/280)
scripts/apn/set-apn.sh lightspeed    # US Mobile Light Speed, T-Mobile network (310/240)
```

It refuses when no SIM in the phone has that network code. It prints the row it used and an `undo:` command
that restores the previous preferred APN and deletes any row it added. You can also delete the APN in
Settings > Network & internet > SIMs > Access Point Names.

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
IPv4 connections open but get no replies. With the script's IPv4 APN the phone gets a native IPv4 address and
IPv4 works. Details are an open item in [`LEDGER.md`](../LEDGER.md).
