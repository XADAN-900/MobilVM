package app.strata.vm;

import org.json.JSONObject;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

/** Bir sanal makinenin ayarları. Flutter ile Map olarak, diskte JSON olarak taşınır. */
final class VmConfig {
    String id = "";
    String name = "VM";
    String template = "custom";
    String arch = "x86_64";        // x86_16 | x86_32 | x86_64 | arm64 | arm32 | ppc | ppc64 | riscv64 | m68k
    String machine = "pc";         // pc | q35 | isapc
    String cpuModel = "";          // boş = mimariye göre varsayılan
    int ramMb = 1024;
    int cpus = 1;
    String vga = "std";            // std | cirrus | vmware | virtio | none
    boolean net = false;
    String nic = "e1000";
    String portForwards = "";      // "tcp:2222:22, tcp:8080:80"
    String isoPath = "";
    String diskPath = "";
    String floppyPath = "";
    String boot = "cd";            // cd | disk | floppy
    String keyboard = "en-us";
    boolean tablet = true;
    boolean rtcLocal = true;
    String extraArgs = "";
    boolean savedState = false;    // "Durumu kaydet ile kapatıldı" -> sonraki açılışta -loadvm
    boolean sharedFolder = false;  // telefondaki klasörü FAT sürücü olarak bağla
    String firmware = "bios";      // bios | uefi
    String sound = "auto";         // auto | none | sb16 | ac97 | es1370 | hda | virtio
    boolean clipboard = true;      // ortak pano (qemu-vdagent; misafirde spice-vdagent gerekir)
    boolean sharedWritable = false;// paylaşılan klasöre misafir de yazabilsin
    String kernelPath = "";        // doğrudan çekirdek açılışı (-kernel)
    String initrdPath = "";        // -initrd
    String kernelArgs = "";        // -append
    String biosPath = "";          // özel BIOS / ROM (-bios), ör. Macintosh Quadra ROM
    long createdAt = 0;
    long lastRunAt = 0;

    static VmConfig fromMap(Map<?, ?> m) {
        VmConfig v = new VmConfig();
        v.id = str(m, "id", v.id);
        v.name = str(m, "name", v.name);
        v.template = str(m, "template", v.template);
        v.arch = str(m, "arch", v.arch);
        v.machine = str(m, "machine", v.machine);
        v.cpuModel = str(m, "cpuModel", v.cpuModel);
        v.ramMb = (int) num(m, "ramMb", v.ramMb);
        v.cpus = (int) num(m, "cpus", v.cpus);
        v.vga = str(m, "vga", v.vga);
        v.net = bool(m, "net", v.net);
        v.nic = str(m, "nic", v.nic);
        v.portForwards = str(m, "portForwards", v.portForwards);
        v.isoPath = str(m, "isoPath", v.isoPath);
        v.diskPath = str(m, "diskPath", v.diskPath);
        v.floppyPath = str(m, "floppyPath", v.floppyPath);
        v.boot = str(m, "boot", v.boot);
        v.keyboard = str(m, "keyboard", v.keyboard);
        v.tablet = bool(m, "tablet", v.tablet);
        v.rtcLocal = bool(m, "rtcLocal", v.rtcLocal);
        v.extraArgs = str(m, "extraArgs", v.extraArgs);
        v.savedState = bool(m, "savedState", v.savedState);
        v.sharedFolder = bool(m, "sharedFolder", v.sharedFolder);
        v.firmware = str(m, "firmware", v.firmware);
        v.sound = str(m, "sound", v.sound);
        v.clipboard = bool(m, "clipboard", v.clipboard);
        v.sharedWritable = bool(m, "sharedWritable", v.sharedWritable);
        v.kernelPath = str(m, "kernelPath", v.kernelPath);
        v.initrdPath = str(m, "initrdPath", v.initrdPath);
        v.kernelArgs = str(m, "kernelArgs", v.kernelArgs);
        v.biosPath = str(m, "biosPath", v.biosPath);
        v.createdAt = num(m, "createdAt", 0);
        v.lastRunAt = num(m, "lastRunAt", 0);
        return v;
    }

    Map<String, Object> toMap() {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        m.put("name", name);
        m.put("template", template);
        m.put("arch", arch);
        m.put("machine", machine);
        m.put("cpuModel", cpuModel);
        m.put("ramMb", ramMb);
        m.put("cpus", cpus);
        m.put("vga", vga);
        m.put("net", net);
        m.put("nic", nic);
        m.put("portForwards", portForwards);
        m.put("isoPath", isoPath);
        m.put("diskPath", diskPath);
        m.put("floppyPath", floppyPath);
        m.put("boot", boot);
        m.put("keyboard", keyboard);
        m.put("tablet", tablet);
        m.put("rtcLocal", rtcLocal);
        m.put("extraArgs", extraArgs);
        m.put("savedState", savedState);
        m.put("sharedFolder", sharedFolder);
        m.put("firmware", firmware);
        m.put("sound", sound);
        m.put("clipboard", clipboard);
        m.put("sharedWritable", sharedWritable);
        m.put("kernelPath", kernelPath);
        m.put("initrdPath", initrdPath);
        m.put("kernelArgs", kernelArgs);
        m.put("biosPath", biosPath);
        m.put("createdAt", createdAt);
        m.put("lastRunAt", lastRunAt);
        return m;
    }

    JSONObject toJson() {
        return new JSONObject(toMap());
    }

    static VmConfig fromJson(JSONObject o) {
        Map<String, Object> m = new HashMap<>();
        Iterator<String> it = o.keys();
        while (it.hasNext()) {
            String k = it.next();
            m.put(k, o.opt(k));
        }
        return fromMap(m);
    }

    private static String str(Map<?, ?> m, String k, String def) {
        Object o = m.get(k);
        return o == null || o == JSONObject.NULL ? def : o.toString();
    }

    private static long num(Map<?, ?> m, String k, long def) {
        Object o = m.get(k);
        if (o instanceof Number) return ((Number) o).longValue();
        if (o instanceof String) {
            try { return Long.parseLong((String) o); } catch (NumberFormatException ignored) { }
        }
        return def;
    }

    private static boolean bool(Map<?, ?> m, String k, boolean def) {
        Object o = m.get(k);
        return o instanceof Boolean ? (Boolean) o : def;
    }
}
