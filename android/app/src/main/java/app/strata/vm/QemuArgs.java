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
 *   m68k                     : Macintosh Quadra 800 "q800" (Mac ROM ya da Linux çekirdeği) / m68k "virt"
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
        int tbSize = 512;
        boolean mttcg = true;
        boolean audio = true; // ayarlardan ses kapatıldıysa hiç ses aygıtı eklenmez
    }

    /** Ses aygıtı yalnızca VNC üzerinden telefona akar; QEMU'nun kendi çıkışı "none". */
    static final String AUDIODEV = "snd0";

    /** Eski Sound Blaster dünyası: DOS, Windows 1-3.x ve 9x. */
    private static final java.util.Set<String> SB16_TEMPLATES = new java.util.HashSet<>(java.util.Arrays.asList(
            "win1", "win2", "win31", "win95", "win98", "winme", "freedos", "msdos", "drdos", "pcdos",
            "dos_other", "other16", "win9x_other"));

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
            case "m68k": return "qemu-system-m68k";
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
            case "m68k": return "m68040";
            default: return "max";
        }
    }

    /** Mimarinin kabul ettiği en fazla RAM (MB). */
    static int maxRam(String arch) {
        switch (arch) {
            case "x86_16": return 256;
            case "ppc": return 2048;      // mac99
            case "arm32": return 3072;    // highmem=off
            case "m68k": return 1024;     // q800 en fazla 1 GB
            default: return 65536;
        }
    }

    static int maxCpus(String arch) {
        return arch.equals("ppc") || arch.equals("x86_16") || arch.equals("m68k") ? 1 : 16;
    }

    /** "auto" ses ayarını mimariye ve sisteme göre gerçek aygıta çevirir. */
    static String soundFor(VmConfig vm) {
        String s = vm.sound == null || vm.sound.isEmpty() ? "auto" : vm.sound;
        if (!s.equals("auto")) {
            // ISA kartı yalnızca x86'da; PCI kartları ISA PC ve 68k'da yok
            if (s.equals("sb16") && !isX86(vm.arch)) return "hda";
            if (vm.arch.equals("m68k")) return s.equals("none") ? "none" : "asc";
            if (isX86(vm.arch) && "isapc".equals(vm.machine) && !s.equals("none")) return "sb16";
            return s;
        }
        switch (vm.arch) {
            case "x86_16": return "sb16";
            case "x86_32":
                return "isapc".equals(vm.machine) || SB16_TEMPLATES.contains(vm.template) ? "sb16" : "ac97";
            case "x86_64":
                return SB16_TEMPLATES.contains(vm.template) ? "sb16" : "hda";
            case "m68k": return "virt".equals(vm.machine) ? "none" : "asc"; // Quadra'nın kendi ses yongası
            case "ppc": return "none"; // mac99'da QEMU ses yongası yok; Mac OS'ta PCI ses sürücüsü de yok
            default: return "hda";
        }
    }

    /** Ortak pano için virtio-serial + qemu-vdagent eklenebilir mi? */
    static boolean clipboardCapable(VmConfig vm) {
        if (vm.arch.equals("x86_16") || vm.arch.equals("ppc") || vm.arch.equals("m68k")) return false;
        // DOS / Windows 9x'te bilinmeyen PCI aygıtı her açılışta sürücü sorar
        if (SB16_TEMPLATES.contains(vm.template)) return false;
        return !(isX86(vm.arch) && "isapc".equals(vm.machine));
    }

    /** 68k makinesinin açılabilmesi için çekirdek ya da (Quadra'da) Mac ROM gerekir. */
    static String bootProblem(VmConfig vm) {
        if (!vm.arch.equals("m68k") || !vm.kernelPath.isEmpty()) return null;
        if (!"virt".equals(vm.machine) && !vm.biosPath.isEmpty()) return null;
        return "virt".equals(vm.machine)
                ? "m68k virt needs a Linux kernel (Advanced boot → Kernel)"
                : "Quadra 800 needs a Macintosh ROM (Advanced boot → BIOS/ROM) or a Linux kernel";
    }

    // ------------------------------------------------------------------ komut satırı

    static List<String> build(VmConfig vm, Env env) {
        List<String> a = new ArrayList<>();
        add(a, env.binary, "-L", env.shareDir, "-name", esc(vm.name.isEmpty() ? "VM" : vm.name));
        String problem = bootProblem(vm);
        if (problem != null) throw new IllegalStateException(problem);
        String snd = env.audio ? soundFor(vm) : "none";
        if (isX86(vm.arch)) buildX86(a, vm, env, snd); else buildOther(a, vm, env, snd);
        boot(a, vm);
        sound(a, vm, snd);
        if (vm.clipboard && clipboardCapable(vm)) {
            // Misafirde spice-vdagent çalışıyorsa pano VNC üzerinden telefonla eşitlenir
            add(a, "-chardev", "qemu-vdagent,id=vdagent0,name=vdagent,clipboard=on,mouse=off");
            add(a, "-device", "virtio-serial-pci,id=vser0");
            add(a, "-device", "virtserialport,bus=vser0.0,chardev=vdagent0,name=com.redhat.spice.0");
        }

        add(a, "-display", "none", "-vnc", "127.0.0.1:" + VNC_DISPLAY + (snd.equals("none") ? "" : ",audiodev=" + AUDIODEV));
        add(a, "-qmp", "tcp:127.0.0.1:" + QMP_PORT + ",server=on,wait=off");
        if (!vm.keyboard.trim().isEmpty()) add(a, "-k", vm.keyboard.trim());
        if (vm.savedState) add(a, "-loadvm", SAVED_STATE);
        a.addAll(splitArgs(vm.extraArgs));
        return a;
    }

    /** Doğrudan çekirdek açılışı ve özel BIOS/ROM. */
    private static void boot(List<String> a, VmConfig vm) {
        if (!vm.kernelPath.isEmpty()) {
            add(a, "-kernel", vm.kernelPath);
            if (!vm.initrdPath.isEmpty()) add(a, "-initrd", vm.initrdPath);
            if (!vm.kernelArgs.trim().isEmpty()) add(a, "-append", vm.kernelArgs.trim());
        }
        if (!vm.biosPath.isEmpty()) add(a, "-bios", vm.biosPath);
    }

    private static void sound(List<String> a, VmConfig vm, String snd) {
        if (snd.equals("none")) return;
        add(a, "-audiodev", "none,id=" + AUDIODEV);
        String dev = "audiodev=" + AUDIODEV;
        switch (snd) {
            case "sb16":
                add(a, "-device", "sb16," + dev, "-device", "adlib," + dev);
                break;
            case "ac97": add(a, "-device", "AC97," + dev); break;
            case "es1370": add(a, "-device", "ES1370," + dev); break;
            case "virtio": add(a, "-device", "virtio-sound-pci," + dev); break;
            case "asc": break; // q800: makine özelliği olarak verildi
            default: add(a, "-device", "intel-hda", "-device", "hda-duplex," + dev); break;
        }
    }

    private static boolean customBios(VmConfig vm) { return !vm.biosPath.isEmpty(); }

    private static String sharedDrive(VmConfig vm, Env env) {
        // Yazılabilir: misafirin yazdıkları telefondaki klasöre geçer. Salt okunur: geçici katmana gider.
        return "fat:" + (vm.sharedWritable ? "rw:" : "") + env.sharedDir + ",format=raw" + (vm.sharedWritable ? "" : ",snapshot=on");
    }

    /**
     * x86 "max" işlemcisi yazılımsal emülasyonda 5 seviyeli sayfa tablosunu (la57) da açar; Linux bunu görünce
     * her TLB ıskasında 5 seviye yürür. Kapatınca belleğe erişim belirgin biçimde hızlanır, uyumluluk değişmez.
     */
    static String cpuFor(VmConfig vm) {
        String cpu = vm.cpuModel.trim().isEmpty() ? defaultCpu(vm.arch) : vm.cpuModel.trim();
        if (isX86(vm.arch) && cpu.startsWith("max") && !cpu.contains("la57")) cpu += ",la57=off";
        return cpu;
    }

    /** Linux/BSD'nin hızlı disk yolu: virtio-blk (IDE'de tek komut sırası vardır, kurulum çok yavaşlar). */
    static boolean virtioDisk(VmConfig vm) {
        return "virtio".equals(vm.diskBus) && isX86(vm.arch) && !vm.arch.equals("x86_16") && !"isapc".equals(vm.machine);
    }

    /** Misafirin tercih ettiği ekran çözünürlüğü (EDID). Daha az piksel = yazılımsal çizimde daha hızlı masaüstü. */
    static final int PREF_W = 1024, PREF_H = 768;

    private static void common(List<String> a, VmConfig vm, Env env, int cpus) {
        add(a, "-cpu", cpuFor(vm));
        add(a, "-m", String.valueOf(Math.max(4, Math.min(vm.ramMb, maxRam(vm.arch)))));
        add(a, "-smp", String.valueOf(cpus));
        // Çok çekirdekli TCG: her sanal çekirdek ayrı iş parçacığında
        boolean mttcg = cpus > 1 && env.mttcg;
        add(a, "-accel", "tcg,tb-size=" + env.tbSize + (mttcg ? ",thread=multi" : ""));
    }

    private static void uefi(List<String> a, VmConfig vm, Env env) {
        String[] f = uefiFiles(vm);
        if (f == null || customBios(vm)) return;
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

    private static void buildX86(List<String> a, VmConfig vm, Env env, String snd) {
        String machine = vm.machine.isEmpty() ? "pc" : vm.machine;
        boolean isa = machine.equals("isapc");
        // PC hoparlörü (bip sesleri, eski oyunlar) da telefona gelsin
        add(a, "-M", machine + (snd.equals("none") ? "" : ",pcspk-audiodev=" + AUDIODEV));
        common(a, vm, env, Math.max(1, Math.min(vm.cpus, maxCpus(vm.arch))));
        if (!vm.vga.isEmpty()) add(a, "-vga", vm.vga);
        if (vm.vga.equals("std")) add(a, "-global", "VGA.xres=" + PREF_W, "-global", "VGA.yres=" + PREF_H);
        if (vm.vga.equals("virtio")) add(a, "-global", "virtio-vga.xres=" + PREF_W, "-global", "virtio-vga.yres=" + PREF_H);
        if (!vm.arch.equals("x86_16")) uefi(a, vm, env);

        // Depolama: disk (ide0), CD (ide1-master, her zaman var ki sonradan ISO takılabilsin), disket
        if (!vm.diskPath.isEmpty() && virtioDisk(vm)) {
            add(a, "-drive", "id=hd0,if=none,file=" + esc(vm.diskPath) + ",format=" + diskFormat(vm.diskPath)
                    + ",discard=unmap,detect-zeroes=unmap");
            add(a, "-device", "virtio-blk-pci,drive=hd0,num-queues=" + Math.max(1, Math.min(vm.cpus, 4)));
        } else if (!vm.diskPath.isEmpty()) {
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
            add(a, "-drive", "id=share0,file=" + sharedDrive(vm, env) + ",if=ide,index=1,media=disk");
        }
        if (!vm.floppyPath.isEmpty()) {
            add(a, "-drive", "id=fd0,file=" + esc(vm.floppyPath) + ",format=raw,if=floppy,index=0");
        }

        // PCI kartlarda PXE ROM'u kapat: ek firmware dosyasına gerek kalmaz
        net(a, vm, isa ? "ne2k_isa" : (vm.nic.isEmpty() ? "e1000" : vm.nic) + ",romfile=");
        if (vm.tablet && !isa) add(a, "-usb", "-device", "usb-tablet");

        String order = vm.boot.equals("disk") ? "c" : vm.boot.equals("floppy") ? "a" : "d";
        // Menü yine açılabilir ama SeaBIOS her açılışta 2,5 sn beklemez
        add(a, "-boot", "order=" + order + ",menu=on,splash-time=800");
        if (vm.rtcLocal) add(a, "-rtc", "base=localtime");
    }

    // ------------------------------------------------------------------ ARM, PowerPC, RISC-V

    private static void buildOther(List<String> a, VmConfig vm, Env env, String snd) {
        if (vm.arch.equals("m68k")) {
            buildM68k(a, vm, env, snd);
            return;
        }
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
            add(a, "-drive", "id=share0,file=" + sharedDrive(vm, env) + ",if=ide,index=1,media=disk");
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
            add(a, "-device", "virtio-gpu-pci,xres=" + PREF_W + ",yres=" + PREF_H);
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
            add(a, "-drive", "id=share0,if=none,file=" + sharedDrive(vm, env));
            add(a, "-device", "virtio-blk-pci,drive=share0");
        }
        net(a, vm, "virtio-net-pci,romfile=");
    }

    // ------------------------------------------------------------------ Motorola 68k

    /**
     * q800: Macintosh Quadra 800 (Mac OS 7.1–8.1 için gerçek Mac ROM gerekir; Linux/NetBSD çekirdekle açılır).
     * Diskler SCSI, ekran yerleşik NuBus kartı, klavye/fare ADB, ağ SONIC (dp83932), ses ASC yongası.
     * virt: yalnızca Linux çekirdeğiyle; virtio-mmio aygıtları.
     */
    private static void buildM68k(List<String> a, VmConfig vm, Env env, String snd) {
        boolean virt = "virt".equals(vm.machine);
        add(a, "-M", virt ? "virt" : "q800" + (snd.equals("asc") ? ",audiodev=" + AUDIODEV : ""));
        common(a, vm, env, 1);
        if (virt) {
            add(a, "-device", "virtio-gpu-device", "-device", "virtio-keyboard-device", "-device", "virtio-tablet-device");
            if (!vm.diskPath.isEmpty()) {
                add(a, "-drive", "id=hd0,if=none,file=" + esc(vm.diskPath) + ",format=" + diskFormat(vm.diskPath));
                add(a, "-device", "virtio-blk-device,drive=hd0");
            }
            add(a, "-device", "virtio-scsi-device,id=scsi0");
            add(a, "-drive", "id=cd0,if=none,media=cdrom,readonly=on" + (vm.isoPath.isEmpty() ? ""
                    : ",format=" + cdFormat(vm.isoPath) + ",file=" + esc(vm.isoPath)));
            add(a, "-device", "scsi-cd,drive=cd0,bus=scsi0.0");
            if (vm.sharedFolder && env.sharedDir != null) {
                add(a, "-drive", "id=share0,if=none,file=" + sharedDrive(vm, env));
                add(a, "-device", "virtio-blk-device,drive=share0");
            }
            net(a, vm, "virtio-net-device");
        } else {
            // SCSI kimlikleri: 0 disk, 1 paylaşılan klasör, 3 CD (Mac geleneği)
            if (!vm.diskPath.isEmpty()) {
                add(a, "-drive", "id=hd0,file=" + esc(vm.diskPath) + ",format=" + diskFormat(vm.diskPath)
                        + ",if=scsi,index=0,media=disk");
            }
            if (vm.sharedFolder && env.sharedDir != null) {
                add(a, "-drive", "id=share0,file=" + sharedDrive(vm, env) + ",if=scsi,index=1,media=disk");
            }
            add(a, "-drive", "id=cd0,if=scsi,index=3,media=cdrom" + (vm.isoPath.isEmpty() ? ""
                    : ",format=" + cdFormat(vm.isoPath) + ",file=" + esc(vm.isoPath)));
            // SONIC ağ kartı makineye lehimli: -nic ile bağlanır
            add(a, "-nic", vm.net ? "user,model=dp83932" + hostForwards(vm.portForwards) : "none");
        }
        if (vm.rtcLocal) add(a, "-rtc", "base=localtime");
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
