package app.strata.vm;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/** VM listesi (vms.json) ve uygulama ayarları (settings.json). */
final class Store {
    private Store() {}

    // ------------------------------------------------------------ VM'ler

    static synchronized List<VmConfig> loadVms(Context c) {
        List<VmConfig> out = new ArrayList<>();
        String s = read(new File(c.getFilesDir(), "vms.json"));
        if (s == null) return out;
        try {
            JSONArray arr = new JSONArray(s);
            for (int i = 0; i < arr.length(); i++) out.add(VmConfig.fromJson(arr.getJSONObject(i)));
        } catch (Exception ignored) { }
        return out;
    }

    static synchronized void saveVms(Context c, List<VmConfig> list) {
        JSONArray arr = new JSONArray();
        for (VmConfig v : list) arr.put(v.toJson());
        write(new File(c.getFilesDir(), "vms.json"), arr.toString());
    }

    static synchronized VmConfig getVm(Context c, String id) {
        for (VmConfig v : loadVms(c)) if (v.id.equals(id)) return v;
        return null;
    }

    static synchronized void upsertVm(Context c, VmConfig vm) {
        List<VmConfig> list = loadVms(c);
        boolean found = false;
        for (int i = 0; i < list.size(); i++) {
            if (list.get(i).id.equals(vm.id)) { list.set(i, vm); found = true; break; }
        }
        if (!found) list.add(vm);
        saveVms(c, list);
    }

    static synchronized void deleteVm(Context c, String id) {
        List<VmConfig> list = loadVms(c);
        list.removeIf(v -> v.id.equals(id));
        saveVms(c, list);
    }

    // ------------------------------------------------------------ ayarlar

    static Map<String, Object> defaultSettings() {
        Map<String, Object> m = new HashMap<>();
        m.put("language", "system");   // system | tr | en
        m.put("theme", "dark");        // system | dark | light
        m.put("filter", "smooth");     // smooth | sharp
        m.put("mouseMode", "touch");   // touch | trackpad
        m.put("tbSize", 256);          // TCG çeviri önbelleği (MB)
        m.put("keyboard", "en-us");
        m.put("mttcg", true);          // çok çekirdekli emülasyon
        return m;
    }

    static synchronized Map<String, Object> getSettings(Context c) {
        Map<String, Object> m = defaultSettings();
        String s = read(new File(c.getFilesDir(), "settings.json"));
        if (s != null) {
            try {
                JSONObject o = new JSONObject(s);
                Iterator<String> it = o.keys();
                while (it.hasNext()) {
                    String k = it.next();
                    m.put(k, o.get(k));
                }
            } catch (Exception ignored) { }
        }
        return m;
    }

    static synchronized void saveSettings(Context c, Map<?, ?> m) {
        write(new File(c.getFilesDir(), "settings.json"), new JSONObject(m).toString());
    }

    static int settingInt(Context c, String key, int def) {
        Object o = getSettings(c).get(key);
        return o instanceof Number ? ((Number) o).intValue() : def;
    }

    static boolean settingBool(Context c, String key, boolean def) {
        Object o = getSettings(c).get(key);
        return o instanceof Boolean ? (Boolean) o : def;
    }

    // ------------------------------------------------------------ yardımcılar

    private static String read(File f) {
        if (!f.exists()) return null;
        try {
            return new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
        } catch (Exception e) {
            return null;
        }
    }

    private static void write(File f, String s) {
        File tmp = new File(f.getPath() + ".tmp");
        try (FileOutputStream os = new FileOutputStream(tmp)) {
            os.write(s.getBytes(StandardCharsets.UTF_8));
            os.getFD().sync();
        } catch (Exception e) {
            return;
        }
        //noinspection ResultOfMethodCallIgnored
        tmp.renameTo(f);
    }
}
