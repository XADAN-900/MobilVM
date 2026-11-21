package app.strata.vm;

import android.content.Context;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/** VmConfig'ten QEMU komut satırı üretir. */
final class QemuCommand {
    static final int VNC_DISPLAY = 1;
    static final int VNC_PORT = 5900 + VNC_DISPLAY;
    static final int QMP_PORT = 4445;
    static final String SAVED_STATE = "strata-saved-state";

    private QemuCommand() {}

    static String defaultCpu(String arch) {
        switch (arch) {
            case "x86_16": return "486";
            case "x86_32": return "pentium3";
            default: return "max";
        }
    }

    static List<String> build(Context c, VmConfig vm) {
        File bin = QemuEnv.systemBinary(c, vm.arch);
        if (bin == null) throw new IllegalStateException("QEMU binary not found in APK");
        int tb = Store.settingInt(c, "tbSize", 256);

        List<String> a = new ArrayList<>();
        add(a, bin.getPath(), "-L", QemuEnv.shareDir(c).getPath(), "-name", esc(vm.name.isEmpty() ? "VM" : vm.name));

        String machine = vm.machine.isEmpty() ? "pc" : vm.machine;
        boolean isa = machine.equals("isapc");
        add(a, "-M", machine);
        add(a, "-cpu", vm.cpuModel.trim().isEmpty() ? defaultCpu(vm.arch) : vm.cpuModel.trim());
        add(a, "-m", String.valueOf(Math.max(4, vm.ramMb)));
        add(a, "-smp", String.valueOf(Math.max(1, vm.cpus)));
        add(a, "-accel", "tcg,tb-size=" + tb);
        if (!vm.vga.isEmpty()) add(a, "-vga", vm.vga);

        // Depolama: disk (ide0), CD (ide1-master, her zaman var ki sonradan ISO takılabilsin), disket
        if (!vm.diskPath.isEmpty()) {
            add(a, "-drive", "id=hd0,file=" + esc(vm.diskPath) + ",format=" + diskFormat(vm.diskPath)
                    + ",if=ide,index=0,media=disk");
        }
        if (!vm.isoPath.isEmpty()) {
            add(a, "-drive", "id=cd0,file=" + esc(vm.isoPath) + ",format=raw,if=ide,index=2,media=cdrom");
        } else {
            add(a, "-drive", "id=cd0,if=ide,index=2,media=cdrom");
        }
        if (vm.sharedFolder) {
            // Telefondaki klasör VM'de ikinci sabit disk (FAT) olarak görünür.
            // snapshot=on: misafirin yazdıkları geçici katmana gider, telefondaki dosyalar korunur.
            add(a, "-drive", "id=share0,file=fat:" + QemuEnv.sharedDir(c, vm.id).getPath()
                    + ",format=raw,if=ide,index=1,media=disk,snapshot=on");
        }
        if (!vm.floppyPath.isEmpty()) {
            add(a, "-drive", "id=fd0,file=" + esc(vm.floppyPath) + ",format=raw,if=floppy,index=0");
        }

        // Ağ: QEMU'nun dahili NAT'ı (slirp) + port yönlendirme
        if (vm.net) {
            add(a, "-netdev", "user,id=n0" + hostForwards(vm.portForwards));
            // PCI kartlarda PXE ROM'u kapat: ek firmware dosyasına gerek kalmaz
            add(a, "-device", isa ? "ne2k_isa,netdev=n0"
                    : (vm.nic.isEmpty() ? "e1000" : vm.nic) + ",netdev=n0,romfile=");
        } else {
            add(a, "-nic", "none");
        }

        if (vm.tablet && !isa) add(a, "-usb", "-device", "usb-tablet");

        String order = vm.boot.equals("disk") ? "c" : vm.boot.equals("floppy") ? "a" : "d";
        add(a, "-boot", "order=" + order + ",menu=on");
        if (vm.rtcLocal) add(a, "-rtc", "base=localtime");

        add(a, "-display", "none", "-vnc", "127.0.0.1:" + VNC_DISPLAY);
        add(a, "-qmp", "tcp:127.0.0.1:" + QMP_PORT + ",server=on,wait=off");
        if (!vm.keyboard.trim().isEmpty()) add(a, "-k", vm.keyboard.trim());
        if (vm.savedState) add(a, "-loadvm", SAVED_STATE);

        a.addAll(splitArgs(vm.extraArgs));
        return a;
    }

    static String diskFormat(String path) {
        String p = path.toLowerCase(Locale.ROOT);
        if (p.endsWith(".qcow2") || p.endsWith(".qcow")) return "qcow2";
        if (p.endsWith(".vdi")) return "vdi";
        if (p.endsWith(".vmdk")) return "vmdk";
        if (p.endsWith(".vhd")) return "vpc";
        if (p.endsWith(".vhdx")) return "vhdx";
        return "raw";
    }

    /** "tcp:2222:22, udp:5000:5000" -> ",hostfwd=tcp::2222-:22,hostfwd=udp::5000-:5000" */
    static String hostForwards(String spec) {
        StringBuilder sb = new StringBuilder();
        for (String part : spec.split("[,;\\s]+")) {
            String[] f = part.trim().split(":");
            if (f.length == 3 && (f[0].equals("tcp") || f[0].equals("udp"))
                    && f[1].matches("\\d+") && f[2].matches("\\d+")) {
                sb.append(",hostfwd=").append(f[0]).append("::").append(f[1]).append("-:").append(f[2]);
            }
        }
        return sb.toString();
    }

    private static String esc(String path) { return path.replace(",", ",,"); }

    private static void add(List<String> list, String... items) {
        for (String s : items) list.add(s);
    }

    /** Boşluklara göre böler; "tırnak içi" tek argümandır. */
    static List<String> splitArgs(String s) {
        List<String> out = new ArrayList<>();
        StringBuilder cur = new StringBuilder();
        char quote = 0;
        boolean has = false;
        for (char ch : s.toCharArray()) {
            if (quote != 0 && ch == quote) {
                quote = 0;
            } else if (quote == 0 && (ch == '"' || ch == '\'')) {
                quote = ch;
                has = true;
            } else if (quote == 0 && Character.isWhitespace(ch)) {
                if (has) { out.add(cur.toString()); cur.setLength(0); has = false; }
            } else {
                cur.append(ch);
                has = true;
            }
        }
        if (has) out.add(cur.toString());
        return out;
    }
}
