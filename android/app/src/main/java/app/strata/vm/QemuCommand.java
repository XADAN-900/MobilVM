package app.strata.vm;

import android.content.Context;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.util.List;

/** Android tarafı: dosya yollarını hazırlar, komut satırını QemuArgs üretir. */
final class QemuCommand {
    static final int VNC_DISPLAY = QemuArgs.VNC_DISPLAY;
    static final int VNC_PORT = QemuArgs.VNC_PORT;
    static final int QMP_PORT = QemuArgs.QMP_PORT;
    static final String SAVED_STATE = QemuArgs.SAVED_STATE;

    private QemuCommand() {}

    static List<String> build(Context c, VmConfig vm) {
        File bin = QemuEnv.systemBinary(c, vm.arch);
        if (bin == null) throw new IllegalStateException("QEMU engine for " + vm.arch + " not found in APK");

        QemuArgs.Env env = new QemuArgs.Env();
        env.binary = bin.getPath();
        env.shareDir = QemuEnv.shareDir(c).getPath();
        env.sharedDir = vm.sharedFolder ? QemuEnv.sharedDir(c, vm.id).getPath() : null;
        env.tbSize = tbCacheMb(c, Store.settingInt(c, "tbCache", 0));
        env.mttcg = Store.settingBool(c, "mttcg", true);
        env.audio = Store.settingBool(c, "sound", true);

        // UEFI: kod salt okunur, değişkenler VM'e (ve mimariye) özel kopyada
        String[] uefi = QemuArgs.uefiFiles(vm);
        if (uefi != null) {
            File code = new File(QemuEnv.shareDir(c), uefi[0]);
            File template = new File(QemuEnv.shareDir(c), uefi[1]);
            if (!code.exists() || !template.exists()) throw new IllegalStateException("Firmware missing: " + uefi[0]);
            File vars = nvramFile(c, vm);
            if (!vars.exists() || vars.length() != template.length()) {
                //noinspection ResultOfMethodCallIgnored
                vars.getParentFile().mkdirs();
                try {
                    Files.copy(template.toPath(), vars.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                } catch (IOException e) {
                    throw new IllegalStateException("UEFI vars: " + e.getMessage());
                }
            }
            env.nvramFile = vars.getPath();
        }
        return QemuArgs.build(vm, env);
    }

    static File nvramFile(Context c, VmConfig vm) {
        return new File(new File(c.getFilesDir(), "nvram"),
                vm.id.replaceAll("[^A-Za-z0-9-]", "_") + "-" + vm.arch + ".fd");
    }

    static String diskFormat(String path) { return QemuArgs.diskFormat(path); }

    /**
     * TCG çeviri önbelleği. Küçükse büyük masaüstü sistemlerde önbellek dolar, her şey yeniden çevrilir
     * ve sistem sürünür. 0 = otomatik: telefon belleğinin 1/8'i, 256 MB ile 1 GB arası (QEMU'nun kendi varsayılanı gibi).
     */
    static int tbCacheMb(Context c, int setting) {
        if (setting > 0) return setting;
        android.app.ActivityManager am = (android.app.ActivityManager) c.getSystemService(Context.ACTIVITY_SERVICE);
        android.app.ActivityManager.MemoryInfo mi = new android.app.ActivityManager.MemoryInfo();
        am.getMemoryInfo(mi);
        long mb = mi.totalMem / (1024 * 1024);
        return (int) Math.max(256, Math.min(1024, mb / 8));
    }
}
