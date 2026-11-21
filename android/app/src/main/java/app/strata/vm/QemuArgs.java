package app.strata.vm;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * VmConfig -> QEMU komut satırı. Android'e bağımlı değildir: CI'da gerçek QEMU ile açılış testi yapılır
 * (scripts/QemuArgsSmoke.java).
 *
 * Mimariler:
 *   x86_16 / x86_32 / x86_64 : PC (i440FX / Q35 / ISA)
 *   arm64 / arm32            : ARM "virt" + UEFI (edk2)
 *   ppc                      : PowerMac G4 "mac99" + OpenBIOS (Mac OS 9, Mac OS X, Linux)
 *   ppc64                    : IBM POWER "pseries" + SLOF (ppc64el Linux)
 *   riscv64                  : RISC-V "virt" + OpenSBI + UEFI
 */
final class QemuArgs {
    static final int VNC_DISPLAY = 1;
    static final int VNC_PORT = 5900 + VNC_DISPLAY;
    static final int QMP_PORT = 4445;
    static final String SAVED_STATE = "strata-saved-state";

    /** Çalışma ortamı: hangi QEMU ikilisi, firmware klasörü, VM'e özel UEFI değişken dosyası vb. */
    static final class Env {
        String binary;
        String shareDir;
        String nvramFile;   // UEFI değişkenleri (VM'e özel kopya); UEFI kullanılmıyorsa null olabilir
        String sharedDir;   // paylaşılan klasör
        int tbSize = 256;
        boolean mttcg = true;
    }

    private QemuArgs() {}

    // ------------------------------------------------------------------ mimari bilgileri

    static boolean isX86(String arch) { return arch.startsWith("x86"); }

    /** Bu mimari için gereken QEMU ikilisinin adı (APK içinde lib<ad>.so). */
    static String binaryFor(String arch) {
        switch (arch) {
            case "arm64":
            case "arm32": return "qemu-system-aarch64";
            case "ppc":
            case "ppc64": return "qemu-system-ppc64";
            case "riscv64": return "qemu-system-riscv64";
            case "x86_64": return "qemu-system-x86_64";
            default: return "qemu-system-i386";
        }
    }

    /** UEFI kullanılıyorsa: [kod dosyası, değişken şablonu]; kullanılmıyorsa null. */
    static String[] uefiFiles(VmConfig vm) {
        switch (vm.arch) {
            case "arm64": return new String[]{"edk2-aarch64-code.fd", "edk2-arm-vars.fd"};
            case "arm32": return new String[]{"edk2-arm-code.fd", "edk2-arm-vars.fd"};
            case "riscv64": return new String[]{"edk2-riscv-code.fd", "edk2-riscv-vars.fd"};
            case "x86_64":
                return "uefi".equals(vm.firmware) && !"isapc".equals(vm.machine)
                        ? new String[]{"edk2-x86_64-code.fd", "edk2-i386-vars.fd"} : null;
            case "x86_32":
                return "uefi".equals(vm.firmware) && !"isapc".equals(vm.machine)
                        ? new String[]{"edk2-i386-code.fd", "edk2-i386-vars.fd"} : null;
            default: return null;
        }
    }

    static String defaultCpu(String arch) {
        switch (arch) {
            case "x86_16": return "486";
            case "x86_32": return "pentium3";
            case "arm32": return "cortex-a15";
            case "ppc": return "G4";
            case "ppc64": return "POWER9";
            case "riscv64": return "rv64";
            default: return "max";
        }
    }

    /** Mimarinin kabul ettiği en fazla RAM (MB). */
    static int maxRam(String arch) {
        switch (arch) {
            case "x86_16": return 256;
            case "ppc": return 2048;      // mac99
            case "arm32": return 3072;    // highmem=off
            default: return 65536;
        }
    }

    static int maxCpus(String arch) {
        return arch.equals("ppc") || arch.equals("x86_16") ? 1 : 16;
    }

    // ------------------------------------------------------------------ komut satırı

    static List<String> build(VmConfig vm, Env env) {
        List<String> a = new ArrayList<>();
        add(a, env.binary, "-L", env.shareDir, "-name", esc(vm.name.isEmpty() ? "VM" : vm.name));
        if (isX86(vm.arch)) buildX86(a, vm, env); else buildOther(a, vm, env);

        add(a, "-display", "none", "-vnc", "127.0.0.1:" + VNC_DISPLAY);
        add(a, "-qmp", "tcp:127.0.0.1:" + QMP_PORT + ",server=on,wait=off");
        if (!vm.keyboard.trim().isEmpty()) add(a, "-k", vm.keyboard.trim());
        if (vm.savedState) add(a, "-loadvm", SAVED_STATE);
        a.addAll(splitArgs(vm.extraArgs));
        return a;
    }

    private static void common(List<String> a, VmConfig vm, Env env, int cpus) {
        add(a, "-cpu", vm.cpuModel.trim().isEmpty() ? defaultCpu(vm.arch) : vm.cpuModel.trim());
        add(a, "-m", String.valueOf(Math.max(4, Math.min(vm.ramMb, maxRam(vm.arch)))));
        add(a, "-smp", String.valueOf(cpus));
        // Çok çekirdekli TCG: her sanal çekirdek ayrı iş parçacığında
        boolean mttcg = cpus > 1 && env.mttcg;
        add(a, "-accel", "tcg,tb-size=" + env.tbSize + (mttcg ? ",thread=multi" : ""));
    }

    private static void uefi(List<String> a, VmConfig vm, Env env) {
        String[] f = uefiFiles(vm);
        if (f == null) return;
        if (env.nvramFile == null) throw new IllegalStateException("UEFI vars file missing");
        add(a, "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=" + esc(env.shareDir + "/" + f[0]));
        add(a, "-drive", "if=pflash,format=raw,unit=1,file=" + esc(env.nvramFile));
    }

    private static void net(List<String> a, VmConfig vm, String device) {
        if (vm.net) {
            add(a, "-netdev", "user,id=n0" + hostForwards(vm.portForwards));
            add(a, "-device", device + ",netdev=n0");
        } else {
            add(a, "-nic", "none");
        }
    }

    // ------------------------------------------------------------------ x86 (PC)

    private static void buildX86(List<String> a, VmConfig vm, Env env) {
        String machine = vm.machine.isEmpty() ? "pc" : vm.machine;
        boolean isa = machine.equals("isapc");
        add(a, "-M", machine);
        common(a, vm, env, Math.max(1, Math.min(vm.cpus, maxCpus(vm.arch))));
        if (!vm.vga.isEmpty()) add(a, "-vga", vm.vga);
        if (!vm.arch.equals("x86_16")) uefi(a, vm, env);

        // Depolama: disk (ide0), CD (ide1-master, her zaman var ki sonradan ISO takılabilsin), disket
        if (!vm.diskPath.isEmpty()) {
            add(a, "-drive", "id=hd0,file=" + esc(vm.diskPath) + ",format=" + diskFormat(vm.diskPath)
                    + ",if=ide,index=0,media=disk");
        }
        if (!vm.isoPath.isEmpty()) {
            add(a, "-drive", "id=cd0,file=" + esc(vm.isoPath) + ",format=" + cdFormat(vm.isoPath) + ",if=ide,index=2,media=cdrom");
        } else {
            add(a, "-drive", "id=cd0,if=ide,index=2,media=cdrom");
        }
        if (vm.sharedFolder && env.sharedDir != null) {
            // Telefondaki klasör VM'de ikinci sabit disk (FAT); misafirin yazdıkları geçici katmana gider
            add(a, "-drive", "id=share0,file=fat:" + env.sharedDir + ",format=raw,if=ide,index=1,media=disk,snapshot=on");
        }
        if (!vm.floppyPath.isEmpty()) {
            add(a, "-drive", "id=fd0,file=" + esc(vm.floppyPath) + ",format=raw,if=floppy,index=0");
        }

        // PCI kartlarda PXE ROM'u kapat: ek firmware dosyasına gerek kalmaz
        net(a, vm, isa ? "ne2k_isa" : (vm.nic.isEmpty() ? "e1000" : vm.nic) + ",romfile=");
        if (vm.tablet && !isa) add(a, "-usb", "-device", "usb-tablet");

        String order = vm.boot.equals("disk") ? "c" : vm.boot.equals("floppy") ? "a" : "d";
        add(a, "-boot", "order=" + order + ",menu=on");
        if (vm.rtcLocal) add(a, "-rtc", "base=localtime");
    }

    // ------------------------------------------------------------------ ARM, PowerPC, RISC-V

    private static void buildOther(List<String> a, VmConfig vm, Env env) {
        switch (vm.arch) {
            case "arm64":
                add(a, "-M", "virt");
                break;
            case "arm32":
                add(a, "-M", "virt,highmem=off");
                break;
            case "riscv64":
                add(a, "-M", "virt");
                break;
            case "ppc":
                add(a, "-M", "mac99,via=pmu");
                break;
            case "ppc64":
                // TCG'nin desteklemediği Spectre/Meltdown yetenekleri kapalı
                add(a, "-M", "pseries,cap-cfpc=broken,cap-sbbc=broken,cap-ibs=broken,cap-ccf-assist=off");
                break;
            default:
                throw new IllegalStateException("Unknown architecture: " + vm.arch);
        }
        common(a, vm, env, Math.max(1, Math.min(vm.cpus, maxCpus(vm.arch))));

        if (vm.arch.equals("ppc")) {
            buildMac99(a, vm, env);
        } else {
            buildVirtio(a, vm, env);
        }
        if (vm.rtcLocal) add(a, "-rtc", "base=localtime");
    }

    /** PowerMac G4: IDE diskler, OpenBIOS, USB klavye/tablet, sungem ağ kartı. */
    private static void buildMac99(List<String> a, VmConfig vm, Env env) {
        add(a, "-vga", "std");
        if (!vm.diskPath.isEmpty()) {
            add(a, "-drive", "id=hd0,file=" + esc(vm.diskPath) + ",format=" + diskFormat(vm.diskPath)
                    + ",if=ide,index=0,media=disk");
        }
        if (!vm.isoPath.isEmpty()) {
            add(a, "-drive", "id=cd0,file=" + esc(vm.isoPath) + ",format=" + cdFormat(vm.isoPath) + ",if=ide,index=2,media=cdrom");
        } else {
            add(a, "-drive", "id=cd0,if=ide,index=2,media=cdrom");
        }
        if (vm.sharedFolder && env.sharedDir != null) {
            add(a, "-drive", "id=share0,file=fat:" + env.sharedDir + ",format=raw,if=ide,index=1,media=disk,snapshot=on");
        }
        net(a, vm, "sungem");
        add(a, "-device", "usb-kbd", "-device", "usb-tablet");
        add(a, "-boot", vm.boot.equals("disk") ? "c" : "d");
    }

    /** ARM / RISC-V / POWER: virtio disk + SCSI CD, USB klavye/tablet, virtio ağ. */
    private static void buildVirtio(List<String> a, VmConfig vm, Env env) {
        uefi(a, vm, env);
        boolean bootCd = !vm.boot.equals("disk") || vm.diskPath.isEmpty();
        if (vm.arch.equals("ppc64")) {
            add(a, "-vga", "std");
        } else {
            add(a, "-device", "virtio-gpu-pci");
        }
        add(a, "-device", "qemu-xhci,id=xhci", "-device", "usb-kbd,bus=xhci.0", "-device", "usb-tablet,bus=xhci.0");

        if (!vm.diskPath.isEmpty()) {
            add(a, "-drive", "id=hd0,if=none,file=" + esc(vm.diskPath) + ",format=" + diskFormat(vm.diskPath));
            add(a, "-device", "virtio-blk-pci,drive=hd0,bootindex=" + (bootCd ? 1 : 0));
        }
        add(a, "-device", "virtio-scsi-pci,id=scsi0");
        if (!vm.isoPath.isEmpty()) {
            add(a, "-drive", "id=cd0,if=none,media=cdrom,readonly=on,format=" + cdFormat(vm.isoPath) + ",file=" + esc(vm.isoPath));
        } else {
            add(a, "-drive", "id=cd0,if=none,media=cdrom,readonly=on");
        }
        add(a, "-device", "scsi-cd,drive=cd0,bus=scsi0.0,bootindex=" + (bootCd ? 0 : 1));
        if (vm.sharedFolder && env.sharedDir != null) {
            add(a, "-drive", "id=share0,if=none,file=fat:" + env.sharedDir + ",format=raw,snapshot=on");
            add(a, "-device", "virtio-blk-pci,drive=share0");
        }
        net(a, vm, "virtio-net-pci,romfile=");
    }

    // ------------------------------------------------------------------ yardımcılar

    static String diskFormat(String path) {
        String p = path.toLowerCase(Locale.ROOT);
        if (p.endsWith(".qcow2") || p.endsWith(".qcow")) return "qcow2";
        if (p.endsWith(".vdi")) return "vdi";
        if (p.endsWith(".vmdk")) return "vmdk";
        if (p.endsWith(".vhd")) return "vpc";
        if (p.endsWith(".vhdx")) return "vhdx";
        return "raw";
    }

    /** CD imajı biçimi: Apple .dmg için QEMU'nun dmg sürücüsü, diğerleri ham. */
    static String cdFormat(String path) {
        return path.toLowerCase(Locale.ROOT).endsWith(".dmg") ? "dmg" : "raw";
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

    static String esc(String path) { return path.replace(",", ",,"); }

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
