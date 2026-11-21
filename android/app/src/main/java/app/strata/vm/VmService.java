package app.strata.vm;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.List;

/** QEMU sürecini ön plan servisinde çalıştırır: ekran kapansa da VM yaşar. */
public class VmService extends Service {
    static final String ACTION_START = "app.strata.vm.START";
    static final String ACTION_STOP = "app.strata.vm.STOP";
    static final String EXTRA_ID = "id";
    private static final String CHANNEL = "vm";
    private static final int NOTIF_ID = 1;

    private static volatile Process process;
    private static volatile boolean stopRequested;
    private static volatile long startedAt;
    private static volatile String runningId;
    private static volatile String runningName = "";
    private static final StringBuilder LOG = new StringBuilder();

    private PowerManager.WakeLock wakeLock;

    // ------------------------------------------------------------ statik API

    static boolean isRunning() { return runningId != null; }
    static String runningId() { return runningId; }

    static String log() {
        synchronized (LOG) { return LOG.toString(); }
    }

    static void appendLog(String line) {
        synchronized (LOG) {
            LOG.append(line).append('\n');
            if (LOG.length() > 200_000) LOG.delete(0, LOG.length() - 150_000);
        }
    }

    static void start(Context c, String id) {
        Intent i = new Intent(c, VmService.class).setAction(ACTION_START).putExtra(EXTRA_ID, id);
        c.startForegroundService(i);
    }

    static void stop(boolean force) {
        Process p = process;
        if (p == null) return;
        stopRequested = true;
        if (force) p.destroyForcibly(); else p.destroy();
    }

    static long startedAt() { return startedAt; }

    // ------------------------------------------------------------ servis

    @Override
    public IBinder onBind(Intent intent) { return null; }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : null;
        if (ACTION_STOP.equals(action)) {
            stop(false);
            if (!isRunning()) stopSelf();
            return START_NOT_STICKY;
        }

        startFg(getString(R.string.notif_starting));
        String id = intent != null ? intent.getStringExtra(EXTRA_ID) : null;
        VmConfig vm = id != null ? Store.getVm(this, id) : null;
        if (vm == null || isRunning()) {
            if (!isRunning()) { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); }
            return START_NOT_STICKY;
        }
        runningId = vm.id;
        runningName = vm.name;
        vm.lastRunAt = System.currentTimeMillis();
        Store.upsertVm(this, vm);
        Events.emit(Events.of("type", "vm", "running", true, "vmId", vm.id));
        new Thread(() -> runQemu(vm), "qemu").start();
        return START_NOT_STICKY;
    }

    private void runQemu(VmConfig vm) {
        synchronized (LOG) { LOG.setLength(0); }
        int code = -1;
        try {
            QemuEnv.ensureRuntime(this, null);
            List<String> cmd = QemuCommand.build(this, vm);
            appendLog("$ " + String.join(" ", cmd));
            if (vm.savedState) {
                // kayıtlı durum bu açılışta kullanıldı
                VmConfig fresh = Store.getVm(this, vm.id);
                if (fresh != null) { fresh.savedState = false; Store.upsertVm(this, fresh); }
            }

            ProcessBuilder pb = new ProcessBuilder(cmd).redirectErrorStream(true).directory(getFilesDir());
            pb.environment().putAll(QemuEnv.environment(this));
            stopRequested = false;
            Process p = pb.start();
            process = p;
            startedAt = System.currentTimeMillis();

            PowerManager pm = getSystemService(PowerManager.class);
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Strata::qemu");
            wakeLock.acquire();
            notifyText(getString(R.string.notif_running, vm.name));

            try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = r.readLine()) != null) appendLog(line);
            } catch (java.io.IOException readErr) {
                // Süreç kapatılırken çıktı akışı kapanır: hata değil
            }
            code = p.waitFor();
            long secs = (System.currentTimeMillis() - startedAt) / 1000;
            if (stopRequested) {
                appendLog("[VM kapatıldı / stopped by user after " + secs + " s]");
                code = 0;
            } else {
                appendLog("[QEMU exited with code " + code + " after " + secs + " s]");
            }
        } catch (Throwable t) {
            appendLog("ERROR: " + t.getMessage());
        } finally {
            process = null;
            runningId = null;
            if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
            Events.emit(Events.of("type", "vm", "running", false, "vmId", vm.id, "exitCode", code));
            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();
        }
    }

    private Notification notification(String text) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL, getString(R.string.notif_channel),
                NotificationManager.IMPORTANCE_LOW));

        Intent open = new Intent(this, MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent openPi = PendingIntent.getActivity(this, 0, open,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent stopPi = PendingIntent.getService(this, 1,
                new Intent(this, VmService.class).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

        return new Notification.Builder(this, CHANNEL)
                .setContentTitle("Strata VM")
                .setContentText(text)
                .setSmallIcon(R.drawable.ic_notification)
                .setColor(0xFF7C5CFF)
                .setContentIntent(openPi)
                .setOngoing(true)
                .addAction(new Notification.Action.Builder(
                        Icon.createWithResource(this, R.drawable.ic_notification),
                        getString(R.string.notif_stop), stopPi).build())
                .build();
    }

    private void startFg(String text) {
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notification(text), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIF_ID, notification(text));
        }
    }

    private void notifyText(String text) {
        getSystemService(NotificationManager.class).notify(NOTIF_ID, notification(text));
    }
}
