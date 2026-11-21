package com.mobilvm.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import kotlin.concurrent.thread

/**
 * QEMU sürecini ön plan servisi içinde çalıştırır; ekran kapansa / uygulama arka plana
 * gitse de VM yaşamaya devam eder.
 */
class VmService : Service() {

    companion object {
        private const val EXTRA_VM_ID = "vm_id"
        private const val CHANNEL = "vm"
        private const val NOTIF_ID = 1

        @Volatile private var process: Process? = null
        @Volatile var runningVmId: String? = null
            private set

        private val logBuf = StringBuilder()

        val isRunning get() = process?.isAlive == true || runningVmId != null

        fun log(): String = synchronized(logBuf) { logBuf.toString() }

        private fun appendLog(line: String) = synchronized(logBuf) {
            logBuf.append(line).append('\n')
            if (logBuf.length > 64_000) logBuf.delete(0, logBuf.length - 48_000)
        }

        fun start(ctx: Context, vmId: String) {
            ctx.startForegroundService(Intent(ctx, VmService::class.java).putExtra(EXTRA_VM_ID, vmId))
        }

        /** SIGTERM gönderir; QEMU diskleri düzgünce kapatıp çıkar. */
        fun stop() {
            process?.destroy()
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startFg("Başlatılıyor…")
        val vm = intent?.getStringExtra(EXTRA_VM_ID)?.let { VmRepository.get(this, it) }
        if (vm == null || isRunning) {
            if (!isRunning) stopSelf()
            return START_NOT_STICKY
        }
        runningVmId = vm.id
        thread(name = "qemu-${vm.name}") { runQemu(vm) }
        return START_NOT_STICKY
    }

    private fun runQemu(vm: VmConfig) {
        synchronized(logBuf) { logBuf.setLength(0) }
        try {
            QemuEnv.ensureRuntime(this)
            val cmd = QemuCommand.build(this, vm)
            appendLog("$ " + cmd.joinToString(" "))

            val pb = ProcessBuilder(cmd).redirectErrorStream(true).directory(filesDir)
            pb.environment().putAll(QemuEnv.environment(this))
            val p = pb.start()
            process = p

            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MobilVM::qemu")
                .apply { acquire() }
            notifyText("${vm.name} çalışıyor")

            p.inputStream.bufferedReader().forEachLine { appendLog(it) }
            appendLog("[QEMU kapandı, çıkış kodu ${p.waitFor()}]")
        } catch (t: Throwable) {
            appendLog("HATA: ${t.message ?: t}")
        } finally {
            process = null
            runningVmId = null
            wakeLock?.takeIf { it.isHeld }?.release()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun notification(text: String): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Sanal makine", NotificationManager.IMPORTANCE_LOW))
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, DisplayActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return Notification.Builder(this, CHANNEL)
            .setContentTitle("MobilVM")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    private fun startFg(text: String) {
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notification(text), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notification(text))
        }
    }

    private fun notifyText(text: String) =
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notification(text))
}
