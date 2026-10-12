package lp3treble;

import android.util.Log;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

/**
 * Tells the Qualcomm RIL (qcril) that the Android telephony UI is up, once per oemhook instance (one per SIM slot).
 * Until qcril has heard this, it parks incoming SMS in a power-saving buffer while the screen is off and drops them
 * after about 20 seconds without an acknowledgement. See atel/README.md.
 *
 * <p>Usage (from lp3-atel-ready): app_process / lp3treble.AtelReady [instance ...], default oemhook0 oemhook1.
 */
public final class AtelReady {
    private static final String TAG = "lp3-atel";
    private static final String IFACE = "vendor.qti.hardware.radio.qcrilhook@1.0::IQtiOemHook";
    private static final int OEM_HOOK_RAW_REQUEST = 2; // transaction code observed on stock firmware
    private static final int FLAG_ONEWAY = 1;
    private static final int SET_ATEL_UI_STATUS = 524314;
    private static final byte UI_READY = 1;
    // qcril registers the hook a few seconds after its process starts; give up after about two minutes.
    private static final long[] BACKOFF_MS = {0, 1000, 2000, 4000, 8000, 15000, 30000, 30000, 30000};
    // The call is oneway, so there is no acknowledgement: send once more after qcril has had time to settle.
    // The request only sets a flag, so repeating it is harmless.
    private static final long RESEND_MS = 5000;

    public static void main(String[] args) {
        Set<String> pending = new LinkedHashSet<>();
        for (String a : args.length > 0 ? args : new String[] {"oemhook0", "oemhook1"}) pending.add(a);
        Set<String> sent = new LinkedHashSet<>();
        Map<String, Throwable> lastError = new LinkedHashMap<>();
        try {
            Hidl hidl = new Hidl();
            ArrayList<Byte> payload = payload();
            for (long delay : BACKOFF_MS) {
                if (delay > 0) Thread.sleep(delay);
                for (String inst : new ArrayList<>(pending)) {
                    Throwable err = hidl.send(inst, payload);
                    if (err == null) {
                        pending.remove(inst);
                        sent.add(inst);
                    } else {
                        lastError.put(inst, err);
                    }
                }
                if (pending.isEmpty()) break;
            }
            if (!sent.isEmpty()) {
                Thread.sleep(RESEND_MS);
                for (String inst : sent) hidl.send(inst, payload);
            }
        } catch (Throwable t) { // reflection setup or interrupt: report and stop, never crash
            Log.w(TAG, "giving up", t);
        }
        if (pending.isEmpty()) {
            Log.i(TAG, "ATEL UI ready sent to " + sent);
        } else {
            StringBuilder why = new StringBuilder();
            for (String inst : pending) why.append(' ').append(inst).append('=').append(lastError.get(inst));
            Log.w(TAG, "ATEL UI ready sent to " + sent + "; not reached:" + why);
        }
        // init ignores a oneshot's exit status; exit explicitly so no binder thread keeps the VM alive.
        System.exit(0);
    }

    /** "QOEMHOOK", request id, payload length, payload, in the CPU's native byte order (qcril runs on the AP). */
    private static ArrayList<Byte> payload() {
        ByteBuffer b = ByteBuffer.allocate(8 + 4 + 4 + 1).order(ByteOrder.nativeOrder());
        b.put("QOEMHOOK".getBytes(StandardCharsets.US_ASCII)).putInt(SET_ATEL_UI_STATUS).putInt(1).put(UI_READY);
        ArrayList<Byte> out = new ArrayList<>();
        for (byte x : b.array()) out.add(x);
        return out;
    }

    /** android.os.HwBinder and HwParcel are system APIs, absent from the public SDK, so reach them by reflection. */
    private static final class Hidl {
        private final Method getService;
        private final Method transact;
        private final Method writeInterfaceToken;
        private final Method writeInt32;
        private final Method writeInt8Vector;
        private final Method release;
        private final Class<?> parcel;
        private int serial;

        Hidl() throws ReflectiveOperationException {
            Class<?> hwBinder = Class.forName("android.os.HwBinder");
            Class<?> iHwBinder = Class.forName("android.os.IHwBinder");
            parcel = Class.forName("android.os.HwParcel");
            getService = hwBinder.getMethod("getService", String.class, String.class);
            transact = iHwBinder.getMethod("transact", int.class, parcel, parcel, int.class);
            writeInterfaceToken = parcel.getMethod("writeInterfaceToken", String.class);
            writeInt32 = parcel.getMethod("writeInt32", int.class);
            writeInt8Vector = parcel.getMethod("writeInt8Vector", ArrayList.class);
            release = parcel.getMethod("release");
        }

        /** Null when sent; otherwise why not (not registered yet, died, denied), and the caller retries. */
        Throwable send(String instance, ArrayList<Byte> data) {
            Object req = null;
            Object reply = null;
            try {
                Object binder = getService.invoke(null, IFACE, instance);
                if (binder == null) return new IllegalStateException("null service");
                req = parcel.getConstructor().newInstance();
                reply = parcel.getConstructor().newInstance();
                writeInterfaceToken.invoke(req, IFACE);
                writeInt32.invoke(req, ++serial);
                writeInt8Vector.invoke(req, data);
                transact.invoke(binder, OEM_HOOK_RAW_REQUEST, req, reply, FLAG_ONEWAY);
                return null;
            } catch (InvocationTargetException e) {
                return e.getCause();
            } catch (Throwable t) {
                return t;
            } finally {
                quietRelease(req);
                quietRelease(reply);
            }
        }

        private void quietRelease(Object p) {
            if (p == null) return;
            try {
                release.invoke(p);
            } catch (Throwable ignored) {
                // the process exits right after; a failed release only leaks until then
            }
        }
    }
}
