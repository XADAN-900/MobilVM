package app.strata.vm;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.view.WindowManager;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;

/** Flutter arayüzü ile Java arka planı arasındaki köprü ("strata/backend" + "strata/events"). */
final class StrataBridge implements MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private static final int REQ_PICK = 4101;

    private final Activity activity;
    private final Context ctx;
    private final TextureRegistry textures;
    private final MethodChannel methods;
    private final EventChannel events;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService io = Executors.newCachedThreadPool();

    private MethodChannel.Result pendingPick;
    private DisplaySession display;

    StrataBridge(Activity activity, FlutterEngine engine) {
        this.activity = activity;
        this.ctx = activity.getApplicationContext();
        this.textures = engine.getRenderer();
        methods = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "strata/backend");
        methods.setMethodCallHandler(this);
        events = new EventChannel(engine.getDartExecutor().getBinaryMessenger(), "strata/events");
        events.setStreamHandler(this);
    }

    void dispose() {
        methods.setMethodCallHandler(null);
        events.setStreamHandler(null);
        if (display != null) display.dispose();
        display = null;
        io.shutdown();
    }

    // ------------------------------------------------------------ olay akışı

    @Override
    public void onListen(Object arguments, EventChannel.EventSink sink) { Events.setSink(sink); }

    @Override
    public void onCancel(Object arguments) { Events.setSink(null); }

    // ------------------------------------------------------------ metotlar

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result r) {
        try {
            switch (call.method) {
                case "prepare":
                    bg(r, () -> {
                        QemuEnv.ensureRuntime(ctx, p -> Events.emit(Events.of("type", "setup", "progress", p)));
                        return deviceInfo();
                    });
                    break;
                case "deviceInfo": r.success(deviceInfo()); break;
                case "qemuVersion": bg(r, this::qemuVersion); break;

                case "getSettings": r.success(Store.getSettings(ctx)); break;
                case "saveSettings": Store.saveSettings(ctx, (Map<?, ?>) call.arguments); r.success(null); break;

                case "listVms": {
                    List<Object> out = new ArrayList<>();
                    for (VmConfig v : Store.loadVms(ctx)) out.add(v.toMap());
                    r.success(out);
                    break;
                }
                case "saveVm": {
                    VmConfig v = VmConfig.fromMap((Map<?, ?>) call.arguments);
                    if (v.id.isEmpty()) v.id = UUID.randomUUID().toString();
                    if (v.createdAt == 0) v.createdAt = System.currentTimeMillis();
                    Store.upsertVm(ctx, v);
                    r.success(v.toMap());
                    break;
                }
                case "deleteVm": {
                    String id = call.argument("id");
                    Boolean files = call.argument("deleteFiles");
                    VmConfig v = Store.getVm(ctx, id);
                    if (v != null && Boolean.TRUE.equals(files) && !v.diskPath.isEmpty()) deleteImageFile(v.diskPath);
                    Store.deleteVm(ctx, id);
                    r.success(null);
                    break;
                }

                case "pickFile": pickFile(r); break;
                case "createDisk": {
                    String name = call.argument("name");
                    Number size = call.argument("sizeMb");
                    bg(r, () -> createDisk(name, size == null ? 1024 : size.longValue()));
                    break;
                }
                case "listImages": r.success(listImages()); break;
                case "deleteImage": r.success(deleteImageFile(call.argument("path"))); break;

                case "startVm": VmService.start(ctx, call.argument("id")); r.success(null); break;
                case "stopVm": VmService.stop(Boolean.TRUE.equals(call.argument("force"))); r.success(null); break;
                case "vmState": r.success(Events.of("running", VmService.isRunning(), "vmId", VmService.runningId())); break;
                case "log": r.success(VmService.log()); break;

                case "qmp": {
                    String cmd = call.argument("command");
                    Map<?, ?> args = call.argument("args");
                    bg(r, () -> QmpClient.exec(cmd, args == null ? null : new JSONObject(args)));
                    break;
                }
                case "changeCd": {
                    String path = call.argument("path");
                    bg(r, () -> changeCd(path));
                    break;
                }

                case "displayAttach": {
                    if (display != null) display.dispose();
                    display = new DisplaySession(textures);
                    r.success(display.textureId());
                    break;
                }
                case "displayDetach": {
                    if (display != null) display.dispose();
                    display = null;
                    r.success(null);
                    break;
                }
                case "pointer": {
                    if (display != null) {
                        Number x = call.argument("x"), y = call.argument("y"), b = call.argument("buttons");
                        display.rfb().sendPointer(x.intValue(), y.intValue(), b.intValue());
                    }
                    r.success(null);
                    break;
                }
                case "key": {
                    if (display != null) {
                        Number ks = call.argument("keysym");
                        display.rfb().sendKey(ks.intValue(), Boolean.TRUE.equals(call.argument("down")));
                    }
                    r.success(null);
                    break;
                }
                case "screenshot": {
                    final DisplaySession d = display;
                    bg(r, () -> saveScreenshot(d));
                    break;
                }
                case "keepScreenOn": {
                    boolean on = Boolean.TRUE.equals(call.argument("on"));
                    if (on) activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    else activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    r.success(null);
                    break;
                }
                default:
                    r.notImplemented();
            }
        } catch (Exception e) {
            r.error("ERR", e.getMessage(), null);
        }
    }

    /** İşi arka planda yapar, sonucu ana iş parçacığında döndürür. */
    private void bg(MethodChannel.Result r, Callable<Object> task) {
        io.execute(() -> {
            try {
                Object v = task.call();
                main.post(() -> r.success(v));
            } catch (Throwable t) {
                String msg = t.getMessage() != null ? t.getMessage() : t.toString();
                main.post(() -> r.error("ERR", msg, null));
            }
        });
    }

    // ------------------------------------------------------------ cihaz bilgisi

    private Map<String, Object> deviceInfo() {
        ActivityManager am = ctx.getSystemService(ActivityManager.class);
        ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
        am.getMemoryInfo(mi);
        Map<String, Object> m = new HashMap<>();
        m.put("totalRamMb", (int) (mi.totalMem / (1024 * 1024)));
        m.put("availRamMb", (int) (mi.availMem / (1024 * 1024)));
        m.put("cores", Runtime.getRuntime().availableProcessors());
        m.put("model", Build.MANUFACTURER + " " + Build.MODEL);
        m.put("android", Build.VERSION.RELEASE);
        m.put("abi", Build.SUPPORTED_ABIS.length > 0 ? Build.SUPPORTED_ABIS[0] : "");
        m.put("qemu64", QemuEnv.bin(ctx, QemuEnv.BIN_X86_64) != null);
        m.put("qemu32", QemuEnv.bin(ctx, QemuEnv.BIN_I386) != null);
        m.put("qemuImg", QemuEnv.bin(ctx, QemuEnv.BIN_IMG) != null);
        m.put("runtime", QemuEnv.hasRuntimeAsset(ctx));
        m.put("imagesDir", QemuEnv.imagesDir(ctx).getPath());
        File imgs = QemuEnv.imagesDir(ctx);
        m.put("freeMb", (int) (imgs.getUsableSpace() / (1024 * 1024)));
        return m;
    }

    private Object qemuVersion() throws Exception {
        File bin = QemuEnv.systemBinary(ctx, "x86_64");
        if (bin == null) return "—";
        Object[] res = QemuEnv.run(ctx, Arrays.asList(bin.getPath(), "--version"));
        String out = ((String) res[1]).trim();
        int nl = out.indexOf('\n');
        return nl > 0 ? out.substring(0, nl) : out;
    }

    // ------------------------------------------------------------ dosyalar

    private void pickFile(MethodChannel.Result r) {
        if (pendingPick != null) {
            r.error("BUSY", "picker already open", null);
            return;
        }
        pendingPick = r;
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*");
        activity.startActivityForResult(i, REQ_PICK);
    }

    void onActivityResult(int req, int res, Intent data) {
        if (req != REQ_PICK) return;
        MethodChannel.Result r = pendingPick;
        pendingPick = null;
        if (r == null) return;
        if (res != Activity.RESULT_OK || data == null || data.getData() == null) {
            r.success(null);
            return;
        }
        Uri uri = data.getData();
        bg(r, () -> importFile(uri));
    }

    /** QEMU content:// adreslerini açamaz; dosya images klasörüne kopyalanır (aynısı varsa atlanır). */
    private Object importFile(Uri uri) throws Exception {
        ContentResolver cr = ctx.getContentResolver();
        String name = "file-" + System.currentTimeMillis() + ".img";
        long size = -1;
        try (Cursor c = cr.query(uri, new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                if (!c.isNull(0)) name = c.getString(0).replace('/', '_');
                if (!c.isNull(1)) size = c.getLong(1);
            }
        }
        File target = new File(QemuEnv.imagesDir(ctx), name);
        if (target.exists() && size > 0 && target.length() == size) return target.getPath();

        Events.emit(Events.of("type", "import", "state", "start", "name", name, "progress", 0.0));
        File tmp = new File(target.getPath() + ".part");
        try (InputStream is = cr.openInputStream(uri); OutputStream os = new FileOutputStream(tmp)) {
            if (is == null) throw new IllegalStateException("cannot open file");
            byte[] buf = new byte[1 << 20];
            long total = 0, lastEmit = 0;
            int n;
            while ((n = is.read(buf)) > 0) {
                os.write(buf, 0, n);
                total += n;
                if (size > 0 && total - lastEmit > (16L << 20)) {
                    lastEmit = total;
                    Events.emit(Events.of("type", "import", "state", "progress", "name", name, "progress", (double) total / size));
                }
            }
        } catch (Exception e) {
            //noinspection ResultOfMethodCallIgnored
            tmp.delete();
            Events.emit(Events.of("type", "import", "state", "done", "name", name, "progress", 1.0));
            throw e;
        }
        //noinspection ResultOfMethodCallIgnored
        target.delete();
        if (!tmp.renameTo(target)) throw new IllegalStateException("rename failed");
        Events.emit(Events.of("type", "import", "state", "done", "name", name, "progress", 1.0));
        return target.getPath();
    }

    private Object createDisk(String name, long sizeMb) throws Exception {
        File img = QemuEnv.bin(ctx, QemuEnv.BIN_IMG);
        if (img == null) throw new IllegalStateException("qemu-img not found");
        String safe = (name == null || name.trim().isEmpty() ? "disk" : name).replaceAll("[^A-Za-z0-9_.-]", "_");
        File f = new File(QemuEnv.imagesDir(ctx), safe + ".qcow2");
        if (f.exists()) f = new File(QemuEnv.imagesDir(ctx), safe + "-" + System.currentTimeMillis() + ".qcow2");
        Object[] res = QemuEnv.run(ctx, Arrays.asList(img.getPath(), "create", "-f", "qcow2", f.getPath(), sizeMb + "M"));
        if ((Integer) res[0] != 0) throw new IllegalStateException(((String) res[1]).trim());
        return f.getPath();
    }

    private List<Object> listImages() {
        List<Object> out = new ArrayList<>();
        File[] files = QemuEnv.imagesDir(ctx).listFiles();
        if (files == null) return out;
        Arrays.sort(files, (a, b) -> Long.compare(b.lastModified(), a.lastModified()));
        for (File f : files) {
            if (!f.isFile() || f.getName().endsWith(".part")) continue;
            out.add(Events.of("name", f.getName(), "path", f.getPath(), "size", f.length(), "modified", f.lastModified()));
        }
        return out;
    }

    private boolean deleteImageFile(String path) {
        if (path == null) return false;
        try {
            File f = new File(path).getCanonicalFile();
            String dir = QemuEnv.imagesDir(ctx).getCanonicalPath() + File.separator;
            return f.getPath().startsWith(dir) && f.delete();
        } catch (Exception e) {
            return false;
        }
    }

    // ------------------------------------------------------------ VM kontrolü

    private Object changeCd(String path) throws Exception {
        if (path == null || path.isEmpty()) {
            try {
                return QmpClient.exec("eject", new JSONObject().put("device", "cd0").put("force", true));
            } catch (Exception e) {
                return QmpClient.hmp("eject -f cd0");
            }
        }
        try {
            return QmpClient.exec("blockdev-change-medium",
                    new JSONObject().put("device", "cd0").put("filename", path).put("format", "raw"));
        } catch (Exception e) {
            return QmpClient.hmp("change cd0 \"" + path.replace("\"", "\\\"") + "\" raw");
        }
    }

    private Object saveScreenshot(DisplaySession d) throws Exception {
        if (d == null) throw new IllegalStateException("no display");
        Bitmap bmp = d.snapshot();
        if (bmp == null) throw new IllegalStateException("no frame yet");
        String name = "Strata_" + new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date()) + ".png";
        if (Build.VERSION.SDK_INT >= 29) {
            ContentValues v = new ContentValues();
            v.put(MediaStore.Images.Media.DISPLAY_NAME, name);
            v.put(MediaStore.Images.Media.MIME_TYPE, "image/png");
            v.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Strata");
            Uri uri = ctx.getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, v);
            if (uri == null) throw new IllegalStateException("MediaStore insert failed");
            try (OutputStream os = ctx.getContentResolver().openOutputStream(uri)) {
                bmp.compress(Bitmap.CompressFormat.PNG, 100, os);
            }
            return Environment.DIRECTORY_PICTURES + "/Strata/" + name;
        }
        File dir = ctx.getExternalFilesDir(Environment.DIRECTORY_PICTURES);
        File f = new File(dir, name);
        try (OutputStream os = new FileOutputStream(f)) {
            bmp.compress(Bitmap.CompressFormat.PNG, 100, os);
        }
        return f.getPath();
    }
}
