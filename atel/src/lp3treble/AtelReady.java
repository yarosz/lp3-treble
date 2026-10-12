package lp3treble;

import android.util.Log;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashSet;
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

    public static void main(String[] args) {
        Set<String> pending = new LinkedHashSet<>();
        for (String a : args.length > 0 ? args : new String[] {"oemhook0", "oemhook1"}) pending.add(a);
        Set<String> sent = new LinkedHashSet<>();
        try {
            Hidl hidl = new Hidl();
            ArrayList<Byte> payload = payload();
            for (long delay : BACKOFF_MS) {
                if (delay > 0) Thread.sleep(delay);
                for (String inst : new ArrayList<>(pending)) {
                    if (hidl.send(inst, payload)) {
                        pending.remove(inst);
                        sent.add(inst);
                    }
                }
                if (pending.isEmpty()) break;
            }
        } catch (ReflectiveOperationException | InterruptedException e) {
            Log.w(TAG, "giving up: " + e);
        }
        if (pending.isEmpty()) {
            Log.i(TAG, "ATEL UI ready sent to " + sent);
        } else {
            Log.w(TAG, "ATEL UI ready sent to " + sent + "; not registered: " + pending);
        }
        System.exit(0); // never fail: init must not see an error for a vendor without the hook
    }

    /** "QOEMHOOK", request id, payload length, payload, in the modem's native byte order. */
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
        private final Class<?> parcel;
        private int serial;

        Hidl() throws ReflectiveOperationException {
            Class<?> hwBinder = Class.forName("android.os.HwBinder");
            Class<?> iHwBinder = Class.forName("android.os.IHwBinder");
            parcel = Class.forName("android.os.HwParcel");
            getService = hwBinder.getMethod("getService", String.class, String.class);
            transact = iHwBinder.getMethod("transact", int.class, parcel, parcel, int.class);
        }

        /** False when the instance is not registered (yet) or the call failed; the caller retries. */
        boolean send(String instance, ArrayList<Byte> data) throws ReflectiveOperationException {
            Object binder;
            try {
                binder = getService.invoke(null, IFACE, instance);
            } catch (InvocationTargetException notRegistered) {
                return false;
            }
            if (binder == null) return false;
            Object req = parcel.getConstructor().newInstance();
            Object reply = parcel.getConstructor().newInstance();
            try {
                parcel.getMethod("writeInterfaceToken", String.class).invoke(req, IFACE);
                parcel.getMethod("writeInt32", int.class).invoke(req, ++serial);
                parcel.getMethod("writeInt8Vector", ArrayList.class).invoke(req, data);
                transact.invoke(binder, OEM_HOOK_RAW_REQUEST, req, reply, FLAG_ONEWAY);
                return true;
            } catch (InvocationTargetException died) {
                return false;
            } finally {
                parcel.getMethod("release").invoke(reply);
            }
        }
    }
}
