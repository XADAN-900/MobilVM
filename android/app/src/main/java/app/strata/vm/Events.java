package app.strata.vm;

import android.os.Handler;
import android.os.Looper;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;

/** Flutter'a olay akışı (VM durumu, ekran, kurulum/içe aktarma ilerlemesi). Her zaman ana iş parçacığında gönderir. */
final class Events {
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static EventChannel.EventSink sink;

    private Events() {}

    static void setSink(EventChannel.EventSink s) {
        MAIN.post(() -> sink = s);
    }

    static void emit(Map<String, Object> event) {
        MAIN.post(() -> {
            if (sink != null) sink.success(event);
        });
    }

    static Map<String, Object> of(Object... kv) {
        Map<String, Object> m = new HashMap<>();
        for (int i = 0; i + 1 < kv.length; i += 2) m.put((String) kv[i], kv[i + 1]);
        return m;
    }
}
