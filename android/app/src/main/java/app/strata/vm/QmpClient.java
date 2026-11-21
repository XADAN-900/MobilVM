package app.strata.vm;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/** QEMU Machine Protocol istemcisi: duraklat, devam, sıfırla, ACPI kapat, CD değiştir... */
final class QmpClient {
    private QmpClient() {}

    /** Komutu çalıştırır, "return" değerini Java Map/List/primitive olarak döndürür. */
    static Object exec(String command, JSONObject args) throws Exception {
        return exec(command, args, 8000);
    }

    static synchronized Object exec(String command, JSONObject args, int timeoutMs) throws Exception {
        try (Socket s = new Socket()) {
            s.connect(new InetSocketAddress("127.0.0.1", QemuCommand.QMP_PORT), 2000);
            s.setSoTimeout(timeoutMs);
            BufferedReader r = new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
            Writer w = new OutputStreamWriter(s.getOutputStream(), StandardCharsets.UTF_8);
            r.readLine(); // karşılama
            send(w, new JSONObject().put("execute", "qmp_capabilities"));
            read(r);
            JSONObject cmd = new JSONObject().put("execute", command);
            if (args != null && args.length() > 0) cmd.put("arguments", args);
            send(w, cmd);
            return toJava(read(r).opt("return"));
        }
    }

    static Object hmp(String commandLine) throws Exception {
        return hmp(commandLine, 8000);
    }

    /** HMP komutu çalıştırır; çıktıda hata varsa istisna atar. */
    static String hmp(String commandLine, int timeoutMs) throws Exception {
        Object r = exec("human-monitor-command", new JSONObject().put("command-line", commandLine), timeoutMs);
        String out = r == null ? "" : r.toString().trim();
        String low = out.toLowerCase(java.util.Locale.ROOT);
        if (low.startsWith("error") || low.contains("error:") || low.contains("could not") || low.contains("failed")) {
            throw new IOException(out);
        }
        return out;
    }

    private static void send(Writer w, JSONObject o) throws IOException {
        w.write(o.toString());
        w.write("\n");
        w.flush();
    }

    private static JSONObject read(BufferedReader r) throws Exception {
        String line;
        while ((line = r.readLine()) != null) {
            line = line.trim();
            if (line.isEmpty()) continue;
            JSONObject o = new JSONObject(line);
            if (o.has("error")) throw new IOException(o.getJSONObject("error").optString("desc", "QMP error"));
            if (o.has("return")) return o;
            // "event" satırlarını atla
        }
        throw new IOException("QMP connection closed");
    }

    static Object toJava(Object o) throws Exception {
        if (o == null || o == JSONObject.NULL) return null;
        if (o instanceof JSONObject) {
            JSONObject j = (JSONObject) o;
            Map<String, Object> m = new HashMap<>();
            Iterator<String> it = j.keys();
            while (it.hasNext()) {
                String k = it.next();
                m.put(k, toJava(j.get(k)));
            }
            return m;
        }
        if (o instanceof JSONArray) {
            JSONArray a = (JSONArray) o;
            List<Object> l = new ArrayList<>();
            for (int i = 0; i < a.length(); i++) l.add(toJava(a.get(i)));
            return l;
        }
        return o;
    }
}
