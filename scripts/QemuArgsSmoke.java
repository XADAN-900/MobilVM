package app.strata.vm;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.List;

/**
 * CI açılış testi: QemuArgs'ın her mimari için ürettiği komut satırını bilgisayardaki gerçek QEMU ile başlatır.
 * Her VM için: 6 sn sonra süreç yaşıyor mu, QMP "running" diyor mu, uygulamanın kendi VNC istemcisi (RfbClient)
 * görüntü alıyor mu, ses akışı ve genişletilmiş pano QEMU tarafından onaylanıyor mu?
 *
 * Kullanım: java app.strata.vm.QemuArgsSmoke <firmware klasörü> <çalışma klasörü> <test imajları klasörü>
 */
public class QemuArgsSmoke {
    private static String share;
    private static File work;
    private static File media;

    public static void main(String[] args) throws Exception {
        share = args[0];
        work = new File(args[1]);
        media = new File(args[2]);
        work.mkdirs();
        File disk = new File(work, "disk.qcow2");
        run(List.of("qemu-img", "create", "-q", "-f", "qcow2", disk.getPath(), "256M"));
        File shared = new File(work, "shared");
        shared.mkdirs();
        Files.writeString(new File(shared, "HELLO.TXT").toPath(), "merhaba\n");
        File kernel68k = new File(work, "loop68k.elf");
        Files.write(kernel68k.toPath(), m68kElf());

        List<Object[]> cases = new ArrayList<>();
        cases.add(new Object[]{"x86 16-bit (MS-DOS, disket)", vm("x86_16", v -> {
            v.vga = "cirrus"; v.tablet = false; v.net = false; v.ramMb = 16; v.cpus = 1;
            v.floppyPath = mediaFile("boot16.img"); v.boot = "floppy"; v.diskPath = disk.getPath();
        })});
        cases.add(new Object[]{"x86 16-bit ISA PC + NE2000", vm("x86_16", v -> {
            v.machine = "isapc"; v.vga = "cirrus"; v.tablet = false; v.net = true; v.ramMb = 16;
        })});
        cases.add(new Object[]{"x86 16-bit DOS: Sound Blaster 16 + AdLib + PC hoparlörü", vm("x86_16", v -> {
            v.template = "freedos"; v.vga = "cirrus"; v.tablet = false; v.net = false; v.ramMb = 32;
        })});
        cases.add(new Object[]{"x86 32-bit Windows 98: SB16, pano aygıtı yok", vm("x86_32", v -> {
            v.template = "win98"; v.vga = "cirrus"; v.nic = "pcnet"; v.tablet = false; v.ramMb = 256;
        })});
        cases.add(new Object[]{"x86 64-bit: ES1370 + yazılabilir paylaşılan klasör", vm("x86_64", v -> {
            v.sound = "es1370"; v.ramMb = 512; v.sharedFolder = true; v.sharedWritable = true;
        })});
        cases.add(new Object[]{"x86 64-bit: virtio-sound + doğrudan çekirdek (multiboot)", vm("x86_64", v -> {
            v.sound = "virtio"; v.ramMb = 512; v.kernelPath = mediaFile("mykernel.elf"); v.kernelArgs = "quiet";
        })});
        cases.add(new Object[]{"Motorola 68k Quadra 800 (çekirdek ile)", vm("m68k", v -> {
            v.machine = "q800"; v.ramMb = 128; v.diskPath = disk.getPath(); v.isoPath = mediaFile("myos32.iso");
            v.kernelPath = kernel68k.getPath(); v.kernelArgs = "console=ttyS0"; v.sharedFolder = true;
        })});
        cases.add(new Object[]{"Motorola 68k virt", vm("m68k", v -> {
            v.machine = "virt"; v.ramMb = 256; v.diskPath = disk.getPath(); v.kernelPath = kernel68k.getPath();
        })});
        cases.add(new Object[]{"x86 32-bit (Windows XP profili)", vm("x86_32", v -> {
            v.vga = "cirrus"; v.nic = "rtl8139"; v.ramMb = 512; v.cpus = 1; v.diskPath = disk.getPath();
            v.isoPath = mediaFile("myos32.iso");
        })});
        cases.add(new Object[]{"x86 64-bit BIOS + paylaşılan klasör + port", vm("x86_64", v -> {
            v.ramMb = 512; v.cpus = 2; v.diskPath = disk.getPath(); v.isoPath = mediaFile("myos64.iso");
            v.sharedFolder = true; v.portForwards = "tcp:2222:22, tcp:8080:80";
        })});
        cases.add(new Object[]{"x86 64-bit UEFI + Q35", vm("x86_64", v -> {
            v.machine = "q35"; v.firmware = "uefi"; v.ramMb = 512; v.cpus = 2; v.diskPath = disk.getPath();
        })});
        cases.add(new Object[]{"ARM 64 (virt + UEFI)", vm("arm64", v -> {
            v.ramMb = 512; v.cpus = 2; v.diskPath = disk.getPath(); v.sharedFolder = true;
        })});
        cases.add(new Object[]{"ARM 32 (virt + UEFI)", vm("arm32", v -> {
            v.ramMb = 512; v.cpus = 2; v.diskPath = disk.getPath();
        })});
        cases.add(new Object[]{"PowerPC 32 (PowerMac G4, Mac OS)", vm("ppc", v -> {
            v.ramMb = 512; v.cpus = 1; v.diskPath = disk.getPath();
        })});
        cases.add(new Object[]{"PowerPC 64 (IBM POWER9)", vm("ppc64", v -> {
            v.ramMb = 1024; v.cpus = 2; v.diskPath = disk.getPath();
        })});
        cases.add(new Object[]{"RISC-V 64 (virt + OpenSBI + UEFI)", vm("riscv64", v -> {
            v.ramMb = 1024; v.cpus = 2; v.diskPath = disk.getPath();
        })});

        int failed = 0;
        for (Object[] c : cases) {
            String name = (String) c[0];
            VmConfig v = (VmConfig) c[1];
            try {
                boot(name, v, shared);
                System.out.println("✓ " + name);
            } catch (Exception e) {
                failed++;
                System.out.println("✗ " + name + ": " + e.getMessage());
            }
        }
        System.out.println(cases.size() - failed + "/" + cases.size() + " yapılandırma açıldı");
        System.exit(failed == 0 ? 0 : 1);
    }

    interface Setup { void apply(VmConfig v); }

    static VmConfig vm(String arch, Setup s) {
        VmConfig v = new VmConfig();
        v.id = "smoke-" + arch;
        v.name = "Smoke, " + arch;
        v.arch = arch;
        v.net = true;
        v.nic = "e1000";
        v.keyboard = "tr";
        s.apply(v);
        return v;
    }

    static String mediaFile(String n) {
        File f = new File(media, n);
        return f.exists() ? f.getPath() : "";
    }

    static String hostBinary(String arch) {
        String b = QemuArgs.binaryFor(arch);
        // ppc ve arm32 için bilgisayarda kendi motorları da var ama uygulama 64-bit motorları kullanır
        return b;
    }

    static void boot(String name, VmConfig v, File shared) throws Exception {
        QemuArgs.Env env = new QemuArgs.Env();
        env.binary = hostBinary(v.arch);
        env.shareDir = share;
        env.sharedDir = shared.getPath();
        String[] uefi = QemuArgs.uefiFiles(v);
        if (uefi != null) {
            File vars = new File(work, v.arch + "-vars.fd");
            Files.copy(new File(share, uefi[1]).toPath(), vars.toPath(), StandardCopyOption.REPLACE_EXISTING);
            env.nvramFile = vars.getPath();
        }
        List<String> cmd = QemuArgs.build(v, env);
        System.out.println("\n== " + name + "\n$ " + String.join(" ", cmd));

        Process p = new ProcessBuilder(cmd).redirectErrorStream(true).start();
        StringBuilder log = new StringBuilder();
        Thread reader = new Thread(() -> {
            try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) synchronized (log) { log.append(line).append('\n'); }
            } catch (Exception ignored) { }
        });
        reader.start();
        try {
            Thread.sleep(6000);
            if (!p.isAlive()) throw new IllegalStateException("QEMU kapandı (kod " + p.exitValue() + "):\n" + log);

            // VNC ekranı
            try (Socket s = new Socket()) {
                s.connect(new InetSocketAddress("127.0.0.1", QemuArgs.VNC_PORT), 3000);
                byte[] b = s.getInputStream().readNBytes(12);
                if (!new String(b, StandardCharsets.US_ASCII).startsWith("RFB ")) throw new IllegalStateException("VNC yanıt vermedi");
            }
            // QMP durumu
            String status = qmpStatus();
            if (!status.contains("\"running\"")) throw new IllegalStateException("QMP durumu: " + status + "\n" + log);
            String proto = protocolCheck(v);
            System.out.println("  " + proto);
            synchronized (log) {
                if (log.length() > 0) System.out.print(log);
            }
        } finally {
            p.destroy();
            if (!p.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)) p.destroyForcibly().waitFor();
            reader.join(2000);
            Thread.sleep(500);
        }
    }

    /** Uygulamanın VNC istemcisiyle bağlanır: görüntü, ses onayı, pano yetenekleri. */
    static String protocolCheck(VmConfig v) throws Exception {
        final int[] frames = {0};
        final String[] err = {null};
        final int[] size = {0, 0};
        RfbClient c = new RfbClient("127.0.0.1", QemuArgs.VNC_PORT, new RfbClient.Listener() {
            @Override public void onConnected(int w, int h) { size[0] = w; size[1] = h; }
            @Override public void onResize(int w, int h) { size[0] = w; size[1] = h; }
            @Override public void onFrame() { synchronized (frames) { frames[0]++; } }
            @Override public void onDisconnected(String e) { err[0] = e == null ? "kapandı" : e; }
        });
        c.start();
        try {
            String snd = QemuArgs.soundFor(v);
            boolean wantAudio = !snd.equals("none");
            long end = System.currentTimeMillis() + 10_000;
            while (System.currentTimeMillis() < end) {
                if (err[0] != null) throw new IllegalStateException("VNC: " + err[0]);
                boolean ok;
                synchronized (frames) { ok = frames[0] > 0; }
                if (ok && c.clipboardExt && (!wantAudio || c.audioEnabled)) break;
                Thread.sleep(100);
            }
            synchronized (frames) { if (frames[0] == 0) throw new IllegalStateException("VNC görüntüsü gelmedi"); }
            if (!c.clipboardExt) throw new IllegalStateException("genişletilmiş pano onaylanmadı");
            if (wantAudio && !c.audioEnabled) throw new IllegalStateException("ses akışı (" + snd + ") onaylanmadı");
            // Telefondan VM'e pano metni (UTF-8) bağlantıyı bozmamalı
            c.sendClipboard("Strata çalışıyor ✓");
            Thread.sleep(700);
            if (err[0] != null) throw new IllegalStateException("pano sonrası VNC koptu: " + err[0]);
            int[] dirty;
            synchronized (c.lock) { dirty = c.takeDirtyLocked(); }
            return "VNC " + size[0] + "x" + size[1] + ", ses: " + snd + (c.audioEnabled ? " ✓" : "")
                    + ", pano ✓" + (dirty != null ? ", değişen bölge " + dirty[2] + "x" + dirty[3] : "");
        } finally {
            c.stop();
        }
    }

    /** Sonsuz döngüde bekleyen en küçük m68k ELF çekirdeği ("bra.s ."). */
    static byte[] m68kElf() {
        java.nio.ByteBuffer b = java.nio.ByteBuffer.allocate(0x2004).order(java.nio.ByteOrder.BIG_ENDIAN);
        b.put(new byte[]{0x7f, 'E', 'L', 'F', 1, 2, 1, 0}).put(new byte[8]);
        b.putShort((short) 2).putShort((short) 4).putInt(1).putInt(0x2000) // EXEC, EM_68K, sürüm, giriş
                .putInt(52).putInt(0).putInt(0)                                 // phoff, shoff, flags
                .putShort((short) 52).putShort((short) 32).putShort((short) 1)  // ehsize, phentsize, phnum
                .putShort((short) 0).putShort((short) 0).putShort((short) 0);
        b.putInt(1).putInt(0x2000).putInt(0x2000).putInt(0x2000).putInt(4).putInt(4).putInt(5).putInt(2); // PT_LOAD
        b.position(0x2000);
        b.put(new byte[]{0x60, (byte) 0xFE, 0x4E, 0x71});
        return b.array();
    }

    static String qmpStatus() throws Exception {
        try (Socket s = new Socket()) {
            s.connect(new InetSocketAddress("127.0.0.1", QemuArgs.QMP_PORT), 3000);
            s.setSoTimeout(5000);
            BufferedReader r = new BufferedReader(new InputStreamReader(s.getInputStream(), StandardCharsets.UTF_8));
            OutputStream w = s.getOutputStream();
            r.readLine();
            w.write("{\"execute\":\"qmp_capabilities\"}\n".getBytes(StandardCharsets.UTF_8));
            w.flush();
            r.readLine();
            w.write("{\"execute\":\"query-status\"}\n".getBytes(StandardCharsets.UTF_8));
            w.flush();
            String line;
            while ((line = r.readLine()) != null) if (line.contains("return")) return line;
            return "(yanıt yok)";
        }
    }

    static void run(List<String> cmd) throws Exception {
        Process p = new ProcessBuilder(cmd).inheritIO().start();
        if (p.waitFor() != 0) throw new IllegalStateException("komut başarısız: " + cmd);
    }
}
