package app.strata.vm;

import android.content.Context;
import android.content.pm.PackageManager;

import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * QEMU çalışma ortamı.
 * - Çalıştırılabilirler APK'da jniLibs/arm64-v8a/lib*.so olarak durur; Android onları nativeLibraryDir'e
 *   çıkarır ve oradan exec() izinlidir (Android 10+ uygulama klasöründen exec'i yasaklar).
 * - Bağımlı kütüphaneler + BIOS dosyaları assets/qemu-runtime.zip içindedir; ilk açılışta açılır.
 */
final class QemuEnv {
    static final String BIN_X86_64 = "libqemu-system-x86_64.so";
    static final String BIN_I386 = "libqemu-system-i386.so";
    static final String BIN_IMG = "libqemu-img.so";
    private static final String RUNTIME_ZIP = "qemu-runtime.zip";
    private static final String RUNTIME_INFO = "qemu-runtime.json";

    interface Progress { void on(double p); }

    private QemuEnv() {}

    static File nativeDir(Context c) { return new File(c.getApplicationInfo().nativeLibraryDir); }
    static File runtimeDir(Context c) { return new File(c.getFilesDir(), "qemu"); }
    static File libDir(Context c) { return new File(runtimeDir(c), "lib"); }
    static File shareDir(Context c) { return new File(runtimeDir(c), "share/qemu"); }

    static File imagesDir(Context c) {
        File base = c.getExternalFilesDir(null);
        if (base == null) base = c.getFilesDir();
        File d = new File(base, "images");
        //noinspection ResultOfMethodCallIgnored
        d.mkdirs();
        return d;
    }

    static File bin(Context c, String name) {
        File f = new File(nativeDir(c), name);
        return f.exists() ? f : null;
    }

    /** 16/32-bit için i386 tercih edilir; yoksa x86_64 de gerçek modu ve 32-bit'i çalıştırır. */
    static File systemBinary(Context c, String arch) {
        if ("x86_64".equals(arch)) return bin(c, BIN_X86_64);
        File f = bin(c, BIN_I386);
        return f != null ? f : bin(c, BIN_X86_64);
    }

    static boolean hasRuntimeAsset(Context c) {
        try (InputStream ignored = c.getAssets().open(RUNTIME_ZIP)) {
            return true;
        } catch (IOException e) {
            return false;
        }
    }

    /** Runtime zip'ini gerekiyorsa (ilk kurulum / güncelleme) açar. */
    static synchronized void ensureRuntime(Context c, Progress progress) throws IOException {
        File root = runtimeDir(c);
        File stamp = new File(root, ".stamp");
        String want;
        try {
            want = String.valueOf(c.getPackageManager().getPackageInfo(c.getPackageName(), 0).lastUpdateTime);
        } catch (PackageManager.NameNotFoundException e) {
            want = "0";
        }
        if (stamp.exists() && want.equals(readText(stamp))) {
            if (progress != null) progress.on(1.0);
            return;
        }
        if (!hasRuntimeAsset(c)) throw new IOException("assets/" + RUNTIME_ZIP + " missing");

        deleteRecursive(root);
        //noinspection ResultOfMethodCallIgnored
        root.mkdirs();
        String rootCanon = root.getCanonicalPath() + File.separator;

        long total = 1;
        try (InputStream is = c.getAssets().open(RUNTIME_INFO)) {
            total = Math.max(1, new JSONObject(readStream(is)).optLong("bytes", 1));
        } catch (Exception ignored) { }

        long done = 0;
        double lastReported = -1;
        byte[] buf = new byte[1 << 16];
        try (ZipInputStream zis = new ZipInputStream(new BufferedInputStream(c.getAssets().open(RUNTIME_ZIP), 1 << 16))) {
            ZipEntry e;
            while ((e = zis.getNextEntry()) != null) {
                File out = new File(root, e.getName());
                if (!out.getCanonicalPath().startsWith(rootCanon)) throw new IOException("bad zip entry " + e.getName());
                if (e.isDirectory()) {
                    //noinspection ResultOfMethodCallIgnored
                    out.mkdirs();
                    continue;
                }
                File parent = out.getParentFile();
                //noinspection ResultOfMethodCallIgnored
                if (parent != null) parent.mkdirs();
                try (FileOutputStream os = new FileOutputStream(out)) {
                    int n;
                    while ((n = zis.read(buf)) > 0) {
                        os.write(buf, 0, n);
                        done += n;
                        double p = Math.min(0.99, (double) done / total);
                        if (progress != null && p - lastReported >= 0.01) {
                            lastReported = p;
                            progress.on(p);
                        }
                    }
                }
            }
        }
        Files.write(stamp.toPath(), want.getBytes(StandardCharsets.UTF_8));
        if (progress != null) progress.on(1.0);
    }

    static Map<String, String> environment(Context c) {
        Map<String, String> env = new HashMap<>();
        env.put("LD_LIBRARY_PATH", libDir(c).getPath() + ":" + nativeDir(c).getPath());
        env.put("QEMU_MODULE_DIR", new File(libDir(c), "qemu").getPath());
        env.put("TMPDIR", c.getCacheDir().getPath());
        env.put("HOME", c.getFilesDir().getPath());
        return env;
    }

    /** Kısa süreli bir aracı (qemu-img, --version) çalıştırır. [0]=çıkış kodu, [1]=çıktı. */
    static Object[] run(Context c, List<String> args) throws IOException, InterruptedException {
        ensureRuntime(c, null);
        ProcessBuilder pb = new ProcessBuilder(args).redirectErrorStream(true).directory(c.getFilesDir());
        pb.environment().putAll(environment(c));
        Process p = pb.start();
        String out = readStream(p.getInputStream());
        return new Object[]{p.waitFor(), out};
    }

    static String readStream(InputStream is) throws IOException {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
            String line;
            while ((line = r.readLine()) != null) sb.append(line).append('\n');
        }
        return sb.toString();
    }

    private static String readText(File f) {
        try {
            return new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
        } catch (IOException e) {
            return "";
        }
    }

    static void deleteRecursive(File f) {
        if (f.isDirectory()) {
            File[] kids = f.listFiles();
            if (kids != null) for (File k : kids) deleteRecursive(k);
        }
        //noinspection ResultOfMethodCallIgnored
        f.delete();
    }
}
